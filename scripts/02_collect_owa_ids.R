# TBMM OWA Plan-Butce Komisyonu tutanak ID listesini topla.
# Indirme yapmaz; sadece liste sayfalarini parse eder.
# Cikti: data/processed/owa_butce_ids.csv

suppressPackageStartupMessages({
  library(httr2)
  library(rvest)
  library(xml2)
  library(dplyr)
  library(readr)
  library(fs)
  library(here)
  library(tibble)
})

source(here::here("R", "scraping_helpers.R"))

# ---- Konfigürasyon ----
OUT_PATH <- here::here("data", "processed", "owa_butce_ids.csv")
LOG_FILE <- here::here("logs",
  paste0("owa_collect_ids_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".log"))

fs::dir_create(here::here("data", "processed"))
fs::dir_create(here::here("logs"))

log <- function(msg, level = "INFO") {
  line <- sprintf("[%s] [%s] %s",
                  format(Sys.time(), "%Y-%m-%d %H:%M:%S"), level, msg)
  message(line)
  cat(line, "\n", file = LOG_FILE, append = TRUE)
}

# ---- Hedef dönem / yasama yılı kombinasyonları ----
# Keşif notlarına göre: Dönem 23 yl 3-5, Dönem 24 yl 2-5
# butce_yili: tartışılan bütçenin yılı (görüşme yılı + 1)
HEDEFLER <- tribble(
  ~donem, ~yasama_yili, ~butce_yili,
  23L,    3L,           2009L,
  23L,    4L,           2010L,
  23L,    5L,           2011L,
  24L,    2L,           2012L,
  24L,    3L,           2013L,
  24L,    4L,           2014L,
  24L,    5L,           2015L
)

# ---- Liste sayfası fetch ----
fetch_list_page <- function(url) {
  log(sprintf("Cekiliyor: %s", url))
  tryCatch({
    request(url) |>
      req_user_agent("TBMM Butce Korpusu Arastirma") |>
      req_timeout(60) |>
      req_retry(max_tries = 3, backoff = \(i) i * 3) |>
      req_perform() |>
      resp_body_html()
  }, error = function(e) {
    log(sprintf("HATA: %s", conditionMessage(e)), "ERROR")
    NULL
  })
}

# ---- Her hedef için liste sayfasını çek ve parse et ----
all_rows <- vector("list", nrow(HEDEFLER))

for (i in seq_len(nrow(HEDEFLER))) {
  h   <- HEDEFLER[i, ]
  url <- owa_list_url(h$donem, h$yasama_yili)

  html <- fetch_list_page(url)
  Sys.sleep(1)

  if (is.null(html)) {
    log(sprintf("Donem %d / YL %d: sayfa alinamadi",
                h$donem, h$yasama_yili), "WARN")
    next
  }

  parsed <- parse_owa_tutanak_list(html)
  log(sprintf("Donem %d / YL %d: %d satir parse edildi",
              h$donem, h$yasama_yili, nrow(parsed)))

  if (nrow(parsed) == 0) next

  parsed <- parsed |>
    mutate(
      donem       = h$donem,
      yasama_yili = h$yasama_yili,
      butce_yili  = h$butce_yili,
      tarih       = parse_dmy(tarih_raw),
      kaynak_url  = url,
      is_butce    = is_butce_tutanak(baslik)
    )

  n_butce <- sum(parsed$is_butce, na.rm = TRUE)
  log(sprintf("  -> Butce filtresi: %d / %d tutanak secildi",
              n_butce, nrow(parsed)))

  all_rows[[i]] <- parsed
}

# ---- Birleştir, filtrele, kaydet ----
ids_df <- bind_rows(all_rows) |>
  filter(is_butce) |>
  select(tutanak_id, donem, yasama_yili, butce_yili,
         tarih, tarih_raw, baslik, kaynak_url) |>
  arrange(tarih)

write_csv(ids_df, OUT_PATH)
log(sprintf("TAMAMLANDI: %d butce tutanagi -> %s", nrow(ids_df), OUT_PATH))

# ---- Rapor ----
sep <- paste(rep("=", 65), collapse = "")
cat("\n", sep, "\n", sep = "")
cat("OWA TUTANAK ID TOPLAMA RAPORU\n")
cat(sep, "\n", sep = "")

cat(sprintf("\nToplam butce tutanagi : %d\n", nrow(ids_df)))
cat(sprintf("Cikti dosyasi        : %s\n", OUT_PATH))

cat("\nYila gore dagilim:\n")
print(as.data.frame(count(ids_df, butce_yili)), row.names = FALSE)

cat("\nIlk 10 satir (ID + tarih + baslik):\n")
print(
  as.data.frame(head(select(ids_df, tutanak_id, tarih, baslik), 10)),
  row.names = FALSE
)

cat("\nSon 5 satir:\n")
print(
  as.data.frame(tail(select(ids_df, tutanak_id, tarih, baslik), 5)),
  row.names = FALSE
)

cat("\n", sep, "\n", sep = "")
cat("Onaylarsan scripts/03_scrape_owa.R ile PDF indirmeye gec.\n")
