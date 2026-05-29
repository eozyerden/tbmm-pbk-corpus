# TBMM OWA Plan-Butce Komisyonu tutanaklarini indir + metni cikar.
# Giris : data/processed/owa_butce_ids.csv
# Cikti : data/raw/pdf/owa/  (PDF)
#         data/raw/txt/owa/  (TXT)
#         data/processed/owa_metadata.csv
#
# RUN_MODE = "test" : 5 ornek PDF indir, kalite goster, dur.
# RUN_MODE = "full" : tum 98 PDF indir + metin cikar.

RUN_MODE  <- "full"   # "test" | "full"
TIMEOUT_S <- 60L

suppressPackageStartupMessages({
  library(httr2)
  library(pdftools)
  library(callr)
  library(dplyr)
  library(readr)
  library(fs)
  library(here)
  library(tibble)
})

source(here::here("R", "scraping_helpers.R"))

# ---- Dizinler ----
PDF_DIR  <- here::here("data", "raw", "pdf", "owa")
TXT_DIR  <- here::here("data", "raw", "txt", "owa")
META_PATH <- here::here("data", "processed", "owa_metadata.csv")
LOG_FILE  <- here::here("logs",
  paste0("owa_scrape_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".log"))

fs::dir_create(c(PDF_DIR, TXT_DIR,
                 here::here("data", "processed"),
                 here::here("logs")))

log <- function(msg, level = "INFO") {
  line <- sprintf("[%s] [%s] %s",
                  format(Sys.time(), "%Y-%m-%d %H:%M:%S"), level, msg)
  message(line)
  cat(line, "\n", file = LOG_FILE, append = TRUE)
}

# ---- Giris CSV'sini oku ----
IDS_PATH <- here::here("data", "processed", "owa_butce_ids.csv")
if (!fs::file_exists(IDS_PATH)) stop("Giris dosyasi bulunamadi: ", IDS_PATH)

ids <- read_csv(IDS_PATH, col_types = cols(
  tutanak_id  = col_integer(),
  donem       = col_integer(),
  yasama_yili = col_integer(),
  butce_yili  = col_integer(),
  tarih       = col_date(),
  tarih_raw   = col_character(),
  baslik      = col_character(),
  kaynak_url  = col_character()
)) |> arrange(tarih)

log(sprintf("Giris: %d tutanak | %s - %s",
            nrow(ids), min(ids$tarih), max(ids$tarih)))

# ---- Dosya adlari + yerel yollar ----
# Format: YYYYMMDD_{id}_owa.pdf
ids <- ids |>
  mutate(
    tarih_str     = format(tarih, "%Y%m%d"),
    dosya_adi     = sprintf("%s_%d_owa.pdf", tarih_str, tutanak_id),
    yerel_pdf_yol = fs::path(PDF_DIR, dosya_adi),
    yerel_txt_yol = fs::path(TXT_DIR, sub("\\.pdf$", ".txt", dosya_adi)),
    pdf_url       = owa_pdf_url(tutanak_id),
    tip           = case_when(
      grepl("SUNU", toupper(baslik))  ~ "sunum",
      grepl("GENEL", toupper(baslik)) ~ "genel",
      TRUE                            ~ "gorusme"
    )
  )

# ---- Indirme fonksiyonu ----
download_pdf <- function(url, dest) {
  if (fs::file_exists(dest)) {
    log(sprintf("ATLA (mevcut): %s", fs::path_file(dest)))
    return("atla")
  }
  tryCatch({
    request(url) |>
      req_user_agent("TBMM Butce Korpusu Arastirma") |>
      req_timeout(180) |>
      req_retry(max_tries = 3, backoff = \(i) i * 3) |>
      req_perform(path = dest)
    log(sprintf("OK indir: %s", fs::path_file(dest)))
    "ok"
  }, error = function(e) {
    log(sprintf("HATA indir %s: %s",
                fs::path_file(dest), conditionMessage(e)), "ERROR")
    if (fs::file_exists(dest)) fs::file_delete(dest)
    "hata"
  })
}

# ---- Metin cikarma: callr subprocess + timeout ----
extract_with_timeout <- function(pdf_path, txt_path, timeout_s = TIMEOUT_S) {
  if (fs::file_exists(txt_path)) {
    log(sprintf("ATLA (mevcut TXT): %s", fs::path_file(txt_path)))
    return(list(durum = "atla", sayfa = NA_integer_, hata = NA_character_))
  }

  bg <- callr::r_bg(
    func = function(pdf_path, txt_path) {
      txt <- pdftools::pdf_text(pdf_path)
      con <- file(txt_path, open = "w", encoding = "UTF-8")
      writeLines(txt, con)
      close(con)
      list(sayfa = length(txt),
           chars = sum(nchar(txt)))
    },
    args = list(pdf_path = pdf_path, txt_path = txt_path),
    supervise = TRUE
  )

  t0 <- proc.time()[["elapsed"]]
  bg$wait(timeout = timeout_s * 1000L)
  sure <- proc.time()[["elapsed"]] - t0

  if (bg$is_alive()) {
    bg$kill()
    if (fs::file_exists(txt_path)) fs::file_delete(txt_path)
    log(sprintf("TIMEOUT (%ds): %s", timeout_s, fs::path_file(pdf_path)), "WARN")
    return(list(durum = "timeout", sayfa = NA_integer_, sure = sure,
                hata = sprintf("%ds timeout asildi", timeout_s)))
  }

  if (bg$get_exit_status() != 0L) {
    err <- tryCatch(bg$get_result(), error = function(e) conditionMessage(e))
    if (fs::file_exists(txt_path)) fs::file_delete(txt_path)
    log(sprintf("HATA parse %s: %s",
                fs::path_file(pdf_path), as.character(err)), "ERROR")
    return(list(durum = "hata", sayfa = NA_integer_, sure = sure,
                hata = as.character(err)))
  }

  res <- tryCatch(bg$get_result(),
                  error = function(e) list(sayfa = NA_integer_, chars = NA_integer_))
  log(sprintf("OK: %s | %d sayfa | %.1fs",
              fs::path_file(pdf_path),
              if (is.null(res$sayfa)) NA_integer_ else res$sayfa, sure))
  list(durum = "ok", sayfa = res$sayfa, chars = res$chars,
       sure = sure, hata = NA_character_)
}

# ---- Hedef satirlari sec ----
n <- nrow(ids)
if (RUN_MODE == "test") {
  test_idx  <- unique(c(1L, 2L, 3L, ceiling(n / 2L), n))
  hedefler  <- ids[test_idx, ]
  log(sprintf("TEST MODU: %d tutanak", nrow(hedefler)))
} else {
  hedefler  <- ids
  log(sprintf("TAM CALISTIRMA: %d tutanak", nrow(hedefler)))
}

# ---- Ana dongu: indir + cikar ----
sonuclar <- vector("list", nrow(hedefler))

for (i in seq_len(nrow(hedefler))) {
  row <- hedefler[i, ]

  # 1. PDF indir
  indir_durum <- download_pdf(row$pdf_url, row$yerel_pdf_yol)
  Sys.sleep(1)  # rate limit: max 1/s

  if (indir_durum == "hata") {
    sonuclar[[i]] <- tibble(
      tutanak_id    = row$tutanak_id,
      tarih         = row$tarih,
      baslik        = row$baslik,
      indir_durum   = "hata",
      parse_durum   = NA_character_,
      sayfa_sayisi  = NA_integer_,
      kelime_sayisi = NA_integer_,
      kalite_skoru  = NA_real_,
      sure_sn       = NA_real_,
      hata_mesaji   = "indirilemedi"
    )
    next
  }

  # 2. Metin cikar
  res <- extract_with_timeout(row$yerel_pdf_yol, row$yerel_txt_yol)

  # 3. Kalite skoru + kelime sayisi
  kalite <- NA_real_
  kelime <- NA_integer_
  if (res$durum %in% c("ok", "atla") && fs::file_exists(row$yerel_txt_yol)) {
    txt <- readLines(row$yerel_txt_yol, encoding = "UTF-8", warn = FALSE)
    kalite <- text_quality_score(txt)
    kelime <- length(unlist(strsplit(paste(txt, collapse = " "), "\\s+")))
  }

  sonuclar[[i]] <- tibble(
    tutanak_id    = row$tutanak_id,
    tarih         = row$tarih,
    baslik        = row$baslik,
    indir_durum   = indir_durum,
    parse_durum   = res$durum,
    sayfa_sayisi  = if (!is.null(res$sayfa)) res$sayfa else NA_integer_,
    kelime_sayisi = kelime,
    kalite_skoru  = kalite,
    sure_sn       = if (!is.null(res$sure)) res$sure else NA_real_,
    hata_mesaji   = res$hata
  )

  if (RUN_MODE == "full" && i %% 10 == 0)
    log(sprintf("  %d / %d islendi...", i, nrow(hedefler)))
}

sonuc_df <- bind_rows(sonuclar)

# ---- TEST RAPORU ----
if (RUN_MODE == "test") {
  sep <- paste(rep("=", 65), collapse = "")
  cat("\n", sep, "\n", sep = "")
  cat("TEST RAPORU — OWA PDF\n")
  cat(sep, "\n", sep = "")

  cat("\n(1) KALITE SKORLARI:\n")
  print(as.data.frame(
    select(sonuc_df, tutanak_id, tarih, parse_durum,
           sayfa_sayisi, kelime_sayisi, kalite_skoru)
  ), row.names = FALSE)

  cat("\n(2) ILK 30 SATIR (ilk tutanak):\n")
  ilk_txt <- hedefler$yerel_txt_yol[1]
  if (fs::file_exists(ilk_txt)) {
    satirlar <- readLines(ilk_txt, encoding = "UTF-8", warn = FALSE)
    satirlar <- satirlar[nchar(trimws(satirlar)) > 0]
    cat(head(satirlar, 30), sep = "\n")
  } else {
    cat("  [metin alinamadi]\n")
  }

  cat("\n(3) TURKCE KARAKTER KONTROLU:\n")
  if (fs::file_exists(ilk_txt)) {
    ilk_200 <- paste(head(readLines(ilk_txt, encoding = "UTF-8", warn = FALSE), 20),
                     collapse = " ")
    tr_chars <- c("İ", "Ş", "Ğ", "Ü", "Ö", "Ç", "ı", "ş", "ğ", "ü", "ö", "ç")
    bulunan  <- tr_chars[sapply(tr_chars, function(c) grepl(c, ilk_200, fixed = TRUE))]
    cat("  Bulunan TR karakterler:", paste(bulunan, collapse = " "), "\n")
  }

  cat("\n", sep, "\n", sep = "")
  cat("TEST TAMAMLANDI.\n")
  cat("Kalite 6+ ise RUN_MODE <- 'full' ile tam indirmeye gec.\n")
  quit(status = 0, save = "no")
}

# ---- METADATA CSV: tum satirlari birlestir ----
meta <- ids |>
  left_join(
    sonuc_df |> select(tutanak_id, indir_durum, parse_durum,
                       sayfa_sayisi, kelime_sayisi, kalite_skoru,
                       sure_sn, hata_mesaji),
    by = "tutanak_id"
  ) |>
  mutate(kaynak = "owa") |>
  select(tutanak_id, kaynak, donem, yasama_yili, butce_yili,
         tarih, baslik, tip,
         yerel_pdf_yol, yerel_txt_yol,
         indir_durum, parse_durum,
         sayfa_sayisi, kelime_sayisi, kalite_skoru,
         sure_sn, hata_mesaji)

write_csv(meta, META_PATH)
log(sprintf("Metadata kaydedildi: %s", META_PATH))

# ---- OZET RAPOR ----
n_indir_ok    <- sum(meta$indir_durum %in% c("ok", "atla"), na.rm = TRUE)
n_parse_ok    <- sum(meta$parse_durum %in% c("ok", "atla"), na.rm = TRUE)
n_timeout     <- sum(meta$parse_durum == "timeout", na.rm = TRUE)
n_hata        <- sum(meta$parse_durum == "hata" | meta$indir_durum == "hata",
                     na.rm = TRUE)

pdf_boyut_mb  <- sum(
  fs::file_info(fs::dir_ls(PDF_DIR, glob = "*.pdf"))$size,
  na.rm = TRUE
) / 1e6
txt_boyut_mb  <- sum(
  fs::file_info(fs::dir_ls(TXT_DIR, glob = "*.txt"))$size,
  na.rm = TRUE
) / 1e6

sep <- paste(rep("=", 65), collapse = "")
cat("\n", sep, "\n", sep = "")
cat("TAM CALISTIRMA RAPORU — OWA SCRAPER\n")
cat(sep, "\n", sep = "")

cat(sprintf("\n  Toplam hedef    : %d\n", nrow(meta)))
cat(sprintf("  Indirilen (PDF) : %d\n", n_indir_ok))
cat(sprintf("  Metin OK        : %d\n", n_parse_ok))
cat(sprintf("  Timeout         : %d\n", n_timeout))
cat(sprintf("  Hata            : %d\n", n_hata))
cat(sprintf("  Disk: PDF %.1f MB | TXT %.1f MB\n", pdf_boyut_mb, txt_boyut_mb))

cat("\nYila gore durum:\n")
print(
  as.data.frame(
    count(meta, butce_yili, parse_durum) |> arrange(butce_yili, parse_durum)
  ),
  row.names = FALSE
)

cat("\nKalite skoru dagilimi (parse_durum=ok):\n")
ok_meta <- meta |> filter(parse_durum %in% c("ok", "atla"), !is.na(kalite_skoru))
if (nrow(ok_meta) > 0) {
  cat(sprintf("  Min: %.1f | Medyan: %.1f | Ort: %.1f | Maks: %.1f\n",
              min(ok_meta$kalite_skoru),
              median(ok_meta$kalite_skoru),
              mean(ok_meta$kalite_skoru),
              max(ok_meta$kalite_skoru)))
  cat(sprintf("  Dusuk kalite (<5): %d tutanak\n",
              sum(ok_meta$kalite_skoru < 5, na.rm = TRUE)))
}

cat("\n3 RASTGELE TUTANAK ILK 30 SATIR:\n")
set.seed(42)
ornekler <- ok_meta |>
  filter(fs::file_exists(yerel_txt_yol)) |>
  slice_sample(n = min(3, nrow(ok_meta)))

for (j in seq_len(nrow(ornekler))) {
  cat(sprintf("\n--- Ornek %d: ID=%d | %s | Butce %d ---\n",
              j, ornekler$tutanak_id[j], ornekler$tarih[j],
              ornekler$butce_yili[j]))
  satirlar <- readLines(ornekler$yerel_txt_yol[j],
                        encoding = "UTF-8", warn = FALSE)
  satirlar <- satirlar[nchar(trimws(satirlar)) > 0]
  cat(head(satirlar, 30), sep = "\n")
}

cat("\n", sep, "\n", sep = "")
cat(sprintf("Metadata: %s\n", META_PATH))

# Sorunlu varsa kaydet
sorunlu <- meta |> filter(parse_durum %in% c("timeout", "hata") |
                            indir_durum == "hata")
if (nrow(sorunlu) > 0) {
  soru_path <- here::here("data", "processed", "owa_sorunlu.csv")
  write_csv(sorunlu |> select(tutanak_id, tarih, baslik, indir_durum,
                               parse_durum, hata_mesaji), soru_path)
  cat(sprintf("Sorunlu (%d): %s\n", nrow(sorunlu), soru_path))
}
