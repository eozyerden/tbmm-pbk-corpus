suppressPackageStartupMessages({
  library(readr); library(dplyr); library(here)
})

PDF_DIR <- here("data/raw/pdf/sbb")
TXT_DIR <- here("data/raw/txt/sbb")
LOG_FILE <- here("data/processed/2018_poppler_log.csv")

sorunlu <- read_csv(here("data/processed/sorunlu_pdfler.csv"), show_col_types = FALSE) |>
  filter(durum == "timeout") |>
  pull(dosya_adi)

cat(sprintf("Parse edilecek PDF sayisi: %d\n\n", length(sorunlu)))

results <- list()

for (i in seq_along(sorunlu)) {
  pdf_name <- sorunlu[i]
  pdf_path <- file.path(PDF_DIR, pdf_name)
  txt_name <- sub("\\.pdf$", ".txt", pdf_name)
  txt_path <- file.path(TXT_DIR, txt_name)

  cat(sprintf("[%d/%d] %s ... ", i, length(sorunlu), pdf_name))

  if (!file.exists(pdf_path)) {
    cat("PDF YOK\n")
    results[[i]] <- list(dosya = pdf_name, durum = "pdf_yok", sure_sn = NA, txt_kb = NA)
    next
  }

  t0 <- Sys.time()
  exit_code <- tryCatch({
    system2("pdftotext",
            args = c("-layout", "-enc", "UTF-8", shQuote(pdf_path), shQuote(txt_path)),
            stdout = FALSE, stderr = FALSE, timeout = 120)
  }, error = function(e) -1)
  sure <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  if (exit_code == 0 && file.exists(txt_path)) {
    txt_kb <- round(file.info(txt_path)$size / 1024, 1)
    cat(sprintf("OK (%.1fs, %.1f KB)\n", sure, txt_kb))
    results[[i]] <- list(dosya = pdf_name, durum = "ok", sure_sn = round(sure, 1), txt_kb = txt_kb)
  } else {
    cat(sprintf("BASARISIZ (exit=%d, %.1fs)\n", exit_code, sure))
    results[[i]] <- list(dosya = pdf_name, durum = "basarisiz", sure_sn = round(sure, 1), txt_kb = NA)
  }
}

log_df <- bind_rows(results)
write_csv(log_df, LOG_FILE)

cat("\n=== OZET ===\n")
print(log_df |> count(durum))
cat(sprintf("\nLog: %s\n", LOG_FILE))
