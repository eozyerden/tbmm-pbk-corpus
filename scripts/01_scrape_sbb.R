# SBB Plan ve Butce Komisyonu tutanaklari (2016-2025)
#
# RUN_MODE = "test" : 5 dosya indir, rapor goster, dur.
# RUN_MODE = "full" : tum dosyalari indir.

RUN_MODE <- "full"   # "test" | "full"

suppressPackageStartupMessages({
  library(httr2)
  library(rvest)
  library(xml2)
  library(dplyr)
  library(readr)
  library(fs)
  library(here)
  library(pdftools)
})

source(here::here("R", "scraping_helpers.R"))

# ---- Konfigürasyon ----
SBB_URL   <- "https://www.sbb.gov.tr/tbmm-plan-ve-butce-komisyonu-butce-tutanaklari/"
PDF_DIR   <- here::here("data", "raw", "pdf", "sbb")
TXT_DIR   <- here::here("data", "raw", "txt", "sbb")
META_PATH <- here::here("data", "processed", "sbb_metadata.csv")
LOG_FILE  <- here::here("logs",
  paste0("sbb_scrape_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".log"))

fs::dir_create(c(PDF_DIR, TXT_DIR,
                 here::here("data", "processed"),
                 here::here("logs")))

log <- function(msg, level = "INFO") {
  line <- sprintf("[%s] [%s] %s",
                  format(Sys.time(), "%Y-%m-%d %H:%M:%S"), level, msg)
  message(line)
  cat(line, "\n", file = LOG_FILE, append = TRUE)
}

# ---- 1. Index sayfasini cek ----
log("SBB index cekiliyor...")
page <- request(SBB_URL) |>
  req_user_agent("TBMM Butce Korpusu Arastirma (R/rvest)") |>
  req_timeout(60) |>
  req_retry(max_tries = 3, backoff = \(i) i * 3) |>
  req_perform() |>
  resp_body_html()

# ---- 2. PDF linklerini topla + filtrele ----
nodes <- html_elements(page, "a[href]")
all_links <- tibble(
  link_metni = html_text(nodes, trim = TRUE),
  href       = html_attr(nodes, "href")
)

# Filtre 1: wp-content/uploads + .pdf uzantisi
pdf_raw <- all_links |>
  filter(
    grepl("wp-content/uploads", href, fixed = TRUE),
    grepl("\\.pdf$", href, ignore.case = TRUE)
  )
log(sprintf("Ham PDF linkleri: %d", nrow(pdf_raw)))

# Filtre 2: icerik filtresi -- sadece tutanak/butce sunum linkleri
# (sidebar'daki kurumsal belgeler dislanir)
relevant_pat <- paste0(
  "Görüş",        # Görüş
  "|Bütçe Sunumu",     # Bütçe Sunumu
  "|Tarihli|Tutanak|Sunum"
)
pdf_filtered <- pdf_raw |>
  filter(
    grepl(relevant_pat, link_metni, ignore.case = TRUE) |
    !is.na(sapply(link_metni, parse_tr_date))
  )
log(sprintf("Icerik filtresinden gecen: %d", nrow(pdf_filtered)))

# ---- 3. URL encode + mutlak URL ----
# Turkce karakterli href'leri url_absolute'un NA dondurmemesi icin once encode et
encode_url <- function(href) {
  tryCatch({
    enc <- utils::URLencode(href, reserved = FALSE, repeated = FALSE)
    xml2::url_absolute(enc, SBB_URL)
  }, error = function(e) NA_character_)
}

pdf_meta <- pdf_filtered |>
  mutate(
    pdf_url_ham    = href,
    pdf_url        = sapply(href, encode_url),
    gorusme_tarihi = as.Date(sapply(link_metni, parse_tr_date)),
    tip            = if_else(grepl("[Ss]unum", link_metni), "sunum", "gorusme"),
    ay_no          = as.integer(format(gorusme_tarihi, "%m")),
    butce_yili     = case_when(
      !is.na(ay_no) & ay_no >= 10 ~
        as.integer(format(gorusme_tarihi, "%Y")) + 1L,
      !is.na(ay_no) ~
        as.integer(format(gorusme_tarihi, "%Y")),
      TRUE ~ NA_integer_
    )
  ) |>
  select(-ay_no) |>
  # Ayni gun + tip icin cakismayi onle
  group_by(gorusme_tarihi, tip) |>
  mutate(seq_no = row_number()) |>
  ungroup() |>
  mutate(
    tarih_str     = if_else(!is.na(gorusme_tarihi),
                            format(gorusme_tarihi, "%Y%m%d"),
                            "bilinmiyor"),
    dosya_adi     = sprintf("%s_%s_sbb_%03d.pdf", tarih_str, tip, seq_no),
    yerel_pdf_yol = fs::path(PDF_DIR, dosya_adi),
    yerel_txt_yol = fs::path(TXT_DIR, sub("\\.pdf$", ".txt", dosya_adi)),
    kaynak        = "sbb"
  ) |>
  select(link_metni, pdf_url_ham, pdf_url, gorusme_tarihi, tip,
         butce_yili, dosya_adi, yerel_pdf_yol, yerel_txt_yol, kaynak)

# ---- 4. Metadata kaydet ----
write_csv(pdf_meta, META_PATH)
n_total <- nrow(pdf_meta)
n_valid <- sum(!is.na(pdf_meta$pdf_url))
log(sprintf("Toplam: %d | Gecerli URL: %d | Metadata: %s",
            n_total, n_valid, META_PATH))

# ---- 5. Indirme fonksiyonlari ----
download_pdf <- function(url, dest) {
  if (is.na(url)) {
    log(sprintf("NA URL atlandi: %s", basename(dest)), "WARN")
    return(FALSE)
  }
  if (fs::file_exists(dest)) {
    log(sprintf("ATLA (mevcut): %s", basename(dest)))
    return(TRUE)
  }
  ok <- tryCatch({
    request(url) |>
      req_user_agent("TBMM Butce Korpusu Arastirma (R/rvest)") |>
      req_timeout(180) |>
      req_retry(max_tries = 3, backoff = \(i) i * 3) |>
      req_perform(path = dest)
    TRUE
  }, error = function(e) {
    log(sprintf("HATA indir %s: %s", basename(dest), conditionMessage(e)), "ERROR")
    if (fs::file_exists(dest)) fs::file_delete(dest)
    FALSE
  })
  if (ok) log(sprintf("OK: %s", basename(dest)))
  ok
}

extract_text <- function(pdf_path, txt_path) {
  if (is.na(pdf_path) || !fs::file_exists(pdf_path)) return(NULL)
  if (fs::file_exists(txt_path)) {
    log(sprintf("ATLA (mevcut TXT): %s", basename(txt_path)))
    return(readLines(txt_path, encoding = "UTF-8", warn = FALSE))
  }
  tryCatch({
    txt <- pdftools::pdf_text(pdf_path)
    write_utf8(txt, txt_path)
    txt
  }, error = function(e) {
    log(sprintf("HATA parse %s: %s", basename(pdf_path), conditionMessage(e)), "ERROR")
    NULL
  })
}

# ---- 6. TEST: 5 dosya ----
valid_rows   <- pdf_meta |> filter(!is.na(pdf_url))
n_valid_rows <- nrow(valid_rows)

test_idx  <- unique(c(1, 2, 3, ceiling(n_valid_rows / 2), n_valid_rows))
test_rows <- valid_rows[test_idx, ]

log(sprintf("TEST: %d dosya indiriliyor...", nrow(test_rows)))

test_scores <- numeric(nrow(test_rows))
test_texts  <- vector("list", nrow(test_rows))

for (i in seq_len(nrow(test_rows))) {
  row <- test_rows[i, ]
  ok  <- download_pdf(row$pdf_url, row$yerel_pdf_yol)
  if (ok) {
    Sys.sleep(1)
    txt <- extract_text(row$yerel_pdf_yol, row$yerel_txt_yol)
    test_scores[i] <- if (!is.null(txt)) text_quality_score(txt) else NA_real_
    test_texts[[i]] <- txt
  } else {
    test_scores[i]  <- NA_real_
    test_texts[[i]] <- NULL
  }
}

# ---- 7. TEST RAPORU ----
sep <- paste(rep("=", 65), collapse = "")
cat("\n", sep, "\n", sep = "")
cat("TEST RAPORU\n")
cat(sep, "\n", sep = "")

cat("\n(1) KALITE SKORLARI (0-10):\n")
test_report <- tibble(
  dosya = test_rows$dosya_adi,
  tarih = as.character(test_rows$gorusme_tarihi),
  tip   = test_rows$tip,
  skor  = test_scores
)
print(as.data.frame(test_report), row.names = FALSE)

cat("\n(2) ILK 30 SATIR (", test_rows$dosya_adi[1], "):\n", sep = "")
if (!is.null(test_texts[[1]])) {
  satirlar <- strsplit(paste(test_texts[[1]], collapse = "\n"), "\n")[[1]]
  satirlar <- satirlar[nchar(trimws(satirlar)) > 0]
  cat(head(satirlar, 30), sep = "\n")
} else {
  cat("  [metin alinamadi]\n")
}

cat("\n(3) GENEL SAYILAR:\n")
cat(sprintf("  Toplam PDF bulundu : %d\n", n_total))
cat(sprintf("  Gecerli URL        : %d\n", n_valid))
cat(sprintf("  NA / gecersiz URL  : %d\n", n_total - n_valid))
cat("\nYila gore dagilim (butce_yili x tip):\n")
print(as.data.frame(count(pdf_meta, butce_yili, tip)), row.names = FALSE)

cat("\n", sep, "\n", sep = "")

if (RUN_MODE == "test") {
  cat("TEST TAMAMLANDI. Onaylarsan RUN_MODE <- 'full' ile tam indirme baslatilir.\n")
  quit(status = 0, save = "no")
}

# ---- 8. TAM INDIRME ----
log(sprintf("TAM INDIRME BASLIYOR: %d dosya...", n_valid_rows))
n_ok   <- 0L
n_fail <- 0L

for (i in seq_len(n_valid_rows)) {
  row <- valid_rows[i, ]
  ok  <- download_pdf(row$pdf_url, row$yerel_pdf_yol)
  if (ok) {
    Sys.sleep(1)
    n_ok <- n_ok + 1L
  } else {
    n_fail <- n_fail + 1L
  }
  if (i %% 10 == 0)
    log(sprintf("  %d / %d islendi...", i, n_valid_rows))
}

# Disk kullanimi
pdf_files <- fs::dir_ls(PDF_DIR, glob = "*.pdf")
txt_files <- fs::dir_ls(TXT_DIR, glob = "*.txt")
pdf_mb    <- sum(fs::file_info(pdf_files)$size, na.rm = TRUE) / 1e6
txt_mb    <- sum(fs::file_info(txt_files)$size, na.rm = TRUE) / 1e6

log(sprintf("TAM INDIRME BITTI: %d basarili, %d hatali", n_ok, n_fail))
log(sprintf("Disk: PDF %.1f MB, TXT %.1f MB", pdf_mb, txt_mb))
cat(sprintf("\nToplam: %d PDF, %d TXT | %.1f MB PDF + %.1f MB TXT\n",
            length(pdf_files), length(txt_files), pdf_mb, txt_mb))
