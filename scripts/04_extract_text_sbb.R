# SBB PDF'lerinden metin cikarma — callr subprocess timeout, diagnostik destekli
#
# RUN_MODE = "diag"  : sadece DIAG_FILES listesindeki dosyaları isle
# RUN_MODE = "full"  : tüm PDF'leri isle

RUN_MODE   <- "full"   # "diag" | "full"
TIMEOUT_S  <- 60L      # dosya başına maksimum saniye

DIAG_FILES <- c(
  "20191113_gorusme_sbb_001.pdf",
  "20191114_gorusme_sbb_001.pdf",
  "20191115_gorusme_sbb_001.pdf",
  "20191121_gorusme_sbb_001.pdf"
)

suppressPackageStartupMessages({
  library(pdftools)
  library(callr)
  library(dplyr)
  library(readr)
  library(fs)
  library(here)
  library(png)
})

PDF_DIR  <- here::here("data", "raw", "pdf", "sbb")
TXT_DIR  <- here::here("data", "raw", "txt", "sbb")
IMG_DIR  <- here::here("data", "raw", "img", "sbb_diag")
SORUNLU  <- here::here("data", "processed", "sorunlu_pdfler.csv")
LOG_FILE <- here::here("logs",
  paste0("extract_sbb_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".log"))

fs::dir_create(c(TXT_DIR, IMG_DIR,
                 here::here("data", "processed"),
                 here::here("logs")))

log <- function(msg, level = "INFO") {
  line <- sprintf("[%s] [%s] %s",
                  format(Sys.time(), "%Y-%m-%d %H:%M:%S"), level, msg)
  message(line)
  cat(line, "\n", file = LOG_FILE, append = TRUE)
}

write_utf8 <- function(txt, path) {
  con <- file(path, open = "w", encoding = "UTF-8")
  on.exit(close(con))
  writeLines(txt, con)
}

# Subprocess ile PDF metin cikarma — timeout callr üzerinden
extract_with_timeout <- function(pdf_path, txt_path, timeout_s) {
  bg <- callr::r_bg(
    func = function(pdf_path, txt_path) {
      txt <- pdftools::pdf_text(pdf_path)
      con <- file(txt_path, open = "w", encoding = "UTF-8")
      writeLines(txt, con)
      close(con)
      length(txt)  # sayfa sayisi
    },
    args = list(pdf_path = pdf_path, txt_path = txt_path),
    supervise = TRUE
  )

  t0 <- proc.time()[["elapsed"]]
  bg$wait(timeout = timeout_s * 1000)  # ms
  sure <- proc.time()[["elapsed"]] - t0

  if (bg$is_alive()) {
    bg$kill()
    if (fs::file_exists(txt_path)) fs::file_delete(txt_path)
    return(list(durum = "timeout", sure = sure, hata = "60s timeout asildi"))
  }

  if (bg$get_exit_status() != 0L) {
    err <- tryCatch(bg$get_result(), error = function(e) conditionMessage(e))
    if (fs::file_exists(txt_path)) fs::file_delete(txt_path)
    return(list(durum = "hata", sure = sure, hata = as.character(err)))
  }

  list(durum = "ok", sure = sure, hata = NA_character_)
}

# ---- Hedef dosyalar ----
all_pdfs <- fs::dir_ls(PDF_DIR, glob = "*.pdf")

target_pdfs <- if (RUN_MODE == "diag") {
  paths <- fs::path(PDF_DIR, DIAG_FILES)
  paths[fs::file_exists(paths)]
} else {
  all_pdfs
}

log(sprintf("Mod: %s | Hedef: %d PDF | Timeout: %ds",
            RUN_MODE, length(target_pdfs), TIMEOUT_S))

# ---- Sonuc tablosu ----
results <- tibble(
  dosya_adi    = character(),
  sayfa_sayisi = integer(),
  sure_sn      = numeric(),
  durum        = character(),
  hata_mesaji  = character(),
  txt_yolu     = character()
)

# ---- Her PDF icin isle ----
for (pdf_path in target_pdfs) {
  fname    <- fs::path_file(pdf_path)
  txt_path <- fs::path(TXT_DIR, sub("\\.pdf$", ".txt", fname))

  # pdf_info() de takılabiliyor — 10s subprocess timeout ile sor
  info_bg <- callr::r_bg(
    func = function(p) pdftools::pdf_info(p)$pages,
    args = list(p = pdf_path), supervise = TRUE
  )
  info_bg$wait(timeout = 10000L)
  n_pages <- if (!info_bg$is_alive()) {
    tryCatch(info_bg$get_result(), error = function(e) NA_integer_)
  } else {
    info_bg$kill(); NA_integer_
  }

  log(sprintf("Basliyor: %s (%s sayfa)", fname,
              if (is.na(n_pages)) "?" else n_pages))

  if (fs::file_exists(txt_path)) {
    log(sprintf("ATLA (mevcut): %s", fname))
    results <- bind_rows(results, tibble(
      dosya_adi = fname, sayfa_sayisi = n_pages,
      sure_sn = 0, durum = "atla",
      hata_mesaji = NA_character_, txt_yolu = txt_path
    ))
    next
  }

  sonuc <- extract_with_timeout(pdf_path, txt_path, TIMEOUT_S)

  log(sprintf("%s: %s | %.1f sn | %d sayfa",
              toupper(sonuc$durum), fname, sonuc$sure,
              if (is.na(n_pages)) 0L else n_pages),
      if (sonuc$durum == "ok") "INFO" else "WARN")

  results <- bind_rows(results, tibble(
    dosya_adi    = fname,
    sayfa_sayisi = n_pages,
    sure_sn      = sonuc$sure,
    durum        = sonuc$durum,
    hata_mesaji  = sonuc$hata,
    txt_yolu     = if (sonuc$durum == "ok") txt_path else NA_character_
  ))

  if (RUN_MODE == "full" && which(target_pdfs == pdf_path) %% 20 == 0)
    log(sprintf("  %d / %d islendi...",
                which(target_pdfs == pdf_path), length(target_pdfs)))
}

# ---- Sorunlu: kaydet + rasterize ----
sorunlu <- results |> filter(durum %in% c("timeout", "hata"))

if (nrow(sorunlu) > 0) {
  write_csv(sorunlu, SORUNLU)
  log(sprintf("Sorunlu: %d dosya -> %s", nrow(sorunlu), SORUNLU))

  for (fname in sorunlu$dosya_adi) {
    pdf_path <- fs::path(PDF_DIR, fname)
    img_path <- fs::path(IMG_DIR, sub("\\.pdf$", "_sayfa1.png", fname))

    if (!fs::file_exists(pdf_path) || fs::file_exists(img_path)) next

    render_bg <- callr::r_bg(
      func = function(pdf_path, img_path) {
        img <- pdftools::pdf_render_page(pdf_path, page = 1, dpi = 150)
        png::writePNG(img, img_path)
      },
      args = list(pdf_path = pdf_path, img_path = img_path),
      supervise = TRUE
    )
    render_bg$wait(timeout = 30000L)
    if (!render_bg$is_alive()) {
      log(sprintf("Gorsel: %s", fs::path_file(img_path)))
    } else {
      render_bg$kill()
      log(sprintf("Gorsel TIMEOUT (30s): %s", fname), "WARN")
    }
  }
} else {
  log("Sorunlu dosya yok.")
}

# ---- Ozet rapor ----
sep <- paste(rep("=", 65), collapse = "")
cat("\n", sep, "\n", sep = "")
cat("METIN CIKARMA RAPORU\n")
cat(sep, "\n", sep = "")
cat(sprintf("\n  Mod          : %s\n", RUN_MODE))
cat(sprintf("  Toplam hedef : %d\n", nrow(results)))
cat(sprintf("  Basarili (ok): %d\n", sum(results$durum == "ok")))
cat(sprintf("  Atlandi      : %d\n", sum(results$durum == "atla")))
cat(sprintf("  Timeout      : %d\n", sum(results$durum == "timeout")))
cat(sprintf("  Hata         : %d\n", sum(results$durum == "hata")))

cat("\nSayfa sayisi ve sure (atlanmayanlar):\n")
print(as.data.frame(
  results |>
    filter(durum != "atla") |>
    select(dosya_adi, sayfa_sayisi, sure_sn, durum) |>
    arrange(desc(sure_sn))
), row.names = FALSE)

if (nrow(sorunlu) > 0) {
  cat(sprintf("\nSorunlu CSV  : %s\n", SORUNLU))
  cat(sprintf("PNG gorseller: %s\n", IMG_DIR))
}

cat("\n", sep, "\n", sep = "")
