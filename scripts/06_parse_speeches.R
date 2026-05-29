# Tutanak TXT dosyalarını konuşmacı-bazlı tibble'a dönüştür.
# Girdi : data/raw/txt/sbb/ + data/raw/txt/owa/  (clean TXT)
#         data/processed/sbb_metadata.csv
#         data/processed/owa_metadata.csv
# Çıktı : data/processed/konusmalar.parquet
#
# RUN_MODE = "pilot" : tek bir SBB dosyası, ilk 20 konuşmayı göster, dur.
# RUN_MODE = "full"  : tüm 278 dosya, parquet olarak kaydet.

RUN_MODE <- "full"   # "pilot" | "full"

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(fs)
  library(here)
  library(tibble)
})

source(here::here("R", "parse_helpers.R"))

`%||%` <- function(a, b) if (length(a) == 1L && !is.na(a) && nchar(a) > 0L) a else b

# ---- Metadata oku ----
sbb_meta <- read_csv(
  here("data", "processed", "sbb_metadata.csv"),
  col_types = cols(
    gorusme_tarihi = col_date(),
    butce_yili     = col_integer(),
    yerel_txt_yol  = col_character(),
    kaynak         = col_character(),
    tip            = col_character(),
    .default       = col_character()
  )
) |>
  filter(fs::file_exists(yerel_txt_yol)) |>
  transmute(
    yerel_txt_yol,
    kaynak,
    tarih      = gorusme_tarihi,
    butce_yili,
    dosya_kaynak = dosya_adi
  )

owa_meta <- read_csv(
  here("data", "processed", "owa_metadata.csv"),
  col_types = cols(
    tarih          = col_date(),
    butce_yili     = col_integer(),
    yerel_txt_yol  = col_character(),
    kaynak         = col_character(),
    parse_durum    = col_character(),
    .default       = col_character()
  )
) |>
  filter(parse_durum %in% c("ok", "atla"), fs::file_exists(yerel_txt_yol)) |>
  transmute(
    yerel_txt_yol,
    kaynak,
    tarih,
    butce_yili,
    dosya_kaynak = fs::path_file(yerel_txt_yol)
  )

# ---- Tek dosya parse fonksiyonu ----
parse_one_file <- function(yerel_txt_yol, kaynak, tarih, butce_yili, dosya_kaynak) {
  lines <- tryCatch(
    readLines(yerel_txt_yol, encoding = "UTF-8", warn = FALSE),
    error = function(e) {
      warning(sprintf("Okunamadi: %s — %s", fs::path_file(yerel_txt_yol), e$message))
      character(0L)
    }
  )
  if (length(lines) == 0L) return(NULL)

  lines_clean <- clean_pdf_text(lines)
  split_into_speeches(
    lines        = lines_clean,
    dosya_kaynak = dosya_kaynak,
    kaynak       = kaynak,
    tarih        = tarih,
    butce_yili   = butce_yili
  )
}

# ================================================================
if (RUN_MODE == "pilot") {

  # Pilot dosya: 15 Kasım 2019 SBB görüşmesi
  pilot_dosya <- here("data", "raw", "txt", "sbb", "20191115_gorusme_sbb_001.txt")

  if (!fs::file_exists(pilot_dosya)) {
    stop("Pilot dosya bulunamadı: ", pilot_dosya)
  }

  row <- sbb_meta |> filter(yerel_txt_yol == pilot_dosya)
  if (nrow(row) == 0L) {
    # Metadata'da yoksa tarih/yıl'ı dosya adından çek
    row <- tibble(
      yerel_txt_yol = pilot_dosya,
      kaynak        = "sbb",
      tarih         = as.Date("2019-11-15"),
      butce_yili    = 2020L,
      dosya_kaynak  = fs::path_file(pilot_dosya)
    )
  }

  cat("=== PILOT PARSE ===\n")
  cat(sprintf("Dosya: %s\n", fs::path_file(pilot_dosya)))
  cat(sprintf("Tarih: %s | Bütçe yılı: %d\n\n", row$tarih[1L], row$butce_yili[1L]))

  sonuc <- parse_one_file(
    yerel_txt_yol = row$yerel_txt_yol[1L],
    kaynak        = row$kaynak[1L],
    tarih         = row$tarih[1L],
    butce_yili    = row$butce_yili[1L],
    dosya_kaynak  = row$dosya_kaynak[1L]
  )

  if (is.null(sonuc) || nrow(sonuc) == 0L) {
    stop("Hiç konuşma çıkmadı! Parser hatalı olabilir.")
  }

  cat(sprintf("Toplam konuşma: %d\n", nrow(sonuc)))
  cat(sprintf("Rol dağılımı:\n"))
  print(as.data.frame(count(sonuc, rol, sort = TRUE)), row.names = FALSE)

  cat(sprintf("\nKelime istatistikleri:\n"))
  cat(sprintf("  Min: %d | Medyan: %d | Ort: %.0f | Maks: %d\n",
              min(sonuc$kelime_sayisi),
              median(sonuc$kelime_sayisi),
              mean(sonuc$kelime_sayisi),
              max(sonuc$kelime_sayisi)))
  cat(sprintf("  Kısa (< 20 kelime): %d\n", sum(sonuc$is_kisa)))

  sep <- paste(rep("-", 80), collapse = "")
  cat(sprintf("\n%s\nİLK 20 KONUŞMA\n%s\n", sep, sep))

  ilk20 <- head(sonuc, 20L)
  for (i in seq_len(nrow(ilk20))) {
    r <- ilk20[i, ]
    cat(sprintf("\n[%02d] %s | %s | %s\n",
                r$oturum_sira, r$konusmaci_ham, r$sehir %||% "—", r$rol))
    cat(sprintf("     sade: %s | kelime: %d\n",
                r$konusmaci_sade, r$kelime_sayisi))
    cat(sprintf("     metin: %s\n",
                substr(r$metin, 1L, 150L)))
  }

  cat(sprintf("\n%s\n", sep))
  cat("PILOT TAMAMLANDI. Onaylarsaniz RUN_MODE <- 'full' ile geniş çalıştırın.\n")

} else {
  # ================================================================
  # TAM ÇALIŞTIRMA
  if (!requireNamespace("arrow", quietly = TRUE)) {
    stop("arrow paketi gerekli: renv::install('arrow') ile kur.")
  }
  library(arrow)

  tum_meta <- bind_rows(sbb_meta, owa_meta)
  cat(sprintf("Toplam dosya: %d (SBB: %d, OWA: %d)\n",
              nrow(tum_meta), sum(tum_meta$kaynak == "sbb"),
              sum(tum_meta$kaynak == "owa")))

  LOG_FILE <- here("logs",
                   paste0("parse_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".log"))
  fs::dir_create(here("logs"))

  log <- function(msg) {
    line <- sprintf("[%s] %s", format(Sys.time(), "%H:%M:%S"), msg)
    message(line)
    cat(line, "\n", file = LOG_FILE, append = TRUE)
  }

  tum_sonuclar <- vector("list", nrow(tum_meta))

  for (i in seq_len(nrow(tum_meta))) {
    row <- tum_meta[i, ]
    res <- tryCatch(
      parse_one_file(row$yerel_txt_yol, row$kaynak, row$tarih,
                     row$butce_yili, row$dosya_kaynak),
      error = function(e) {
        log(sprintf("HATA %s: %s", row$dosya_kaynak, e$message))
        NULL
      }
    )
    tum_sonuclar[[i]] <- res

    if (i %% 50 == 0)
      log(sprintf("%d / %d islendi...", i, nrow(tum_meta)))
  }

  korpus <- bind_rows(Filter(Negate(is.null), tum_sonuclar))

  cat(sprintf("\nToplam konuşma satırı: %d\n", nrow(korpus)))

  if (nrow(korpus) < 30000 || nrow(korpus) > 300000) {
    warning(sprintf("BEKLENMEYEN BOYUT: %d satır — parser sorunlu olabilir!", nrow(korpus)))
  }

  out_path <- here("data", "processed", "konusmalar.parquet")
  fs::dir_create(here("data", "processed"))
  write_parquet(korpus, out_path)
  log(sprintf("Kaydedildi: %s (%d satır)", out_path, nrow(korpus)))

  cat("\nYıl × kaynak dağılımı:\n")
  print(as.data.frame(count(korpus, kaynak, butce_yili) |> arrange(kaynak, butce_yili)),
        row.names = FALSE)
}
