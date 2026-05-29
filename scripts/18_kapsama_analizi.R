# Asama 5a.5: PBK butce toplantisi evreni ve kapsama dogrulamasi
# Ciktilar: data/processed/pbk_*.csv, reports/05a5_pbk_toplanti_evreni_raporu.md

suppressPackageStartupMessages({
  library(here); library(readr); library(dplyr); library(stringr)
  library(httr2); library(rvest); library(xml2); library(fs)
  library(tibble); library(tidyr)
})

source(here("R", "scraping_helpers.R"))

cat("=== Asama 5a.5: PBK Butce Toplantisi Evreni ===\n")
cat("Baslangic:", format(Sys.time()), "\n\n")

dir_create(here("data", "processed"))
dir_create(here("reports"))

# ============================================================
# YARDIMCI: Butce/Butce-disi siniflandirma
# ============================================================

KEYWORDS_BUDGET <- c(
  "bütçe", "butce", "kesin hesap", "kesinhesap",
  "sayıştay", "sayistay", "bütçe kanunu", "bütçe ve kesin hesap",
  "merkezi yönetim bütçe", "merkezi yonetim butce"
)
KEYWORDS_NON_BUDGET <- c(
  "kalkınma planı", "kalkinma plani",
  "kanun tasarısı", "kanun tasarisi",
  "merkez bankası", "merkez bankasi",
  "bilgilendirme", "torba kanun", "vergi kanunu teklifi"
)

classify_text <- function(text) {
  if (is.na(text) || nchar(trimws(text)) == 0) {
    return(list(is_budget = NA, budget_reason = NA_character_,
                non_budget_reason = NA_character_,
                confidence = "low", needs_review = TRUE))
  }
  tl <- tolower(text)
  b_hits  <- Filter(function(k) str_detect(tl, fixed(tolower(k))), KEYWORDS_BUDGET)
  nb_hits <- Filter(function(k) str_detect(tl, fixed(tolower(k))), KEYWORDS_NON_BUDGET)
  has_b  <- length(b_hits)  > 0
  has_nb <- length(nb_hits) > 0

  if (has_b && !has_nb) {
    list(is_budget = TRUE,
         budget_reason     = paste(b_hits,  collapse = "; "),
         non_budget_reason = NA_character_, confidence = "high", needs_review = FALSE)
  } else if (has_nb && !has_b) {
    list(is_budget = FALSE,
         budget_reason     = NA_character_,
         non_budget_reason = paste(nb_hits, collapse = "; "), confidence = "high", needs_review = FALSE)
  } else if (has_b && has_nb) {
    list(is_budget = TRUE,
         budget_reason     = paste(b_hits,  collapse = "; "),
         non_budget_reason = paste(nb_hits, collapse = "; "), confidence = "low",  needs_review = TRUE)
  } else {
    list(is_budget = NA,
         budget_reason     = NA_character_,
         non_budget_reason = NA_character_, confidence = "low",  needs_review = TRUE)
  }
}

# ============================================================
# BOLUM A: YEREL DOSYA ENVANTERI
# ============================================================
cat("BOLUM A: Yerel dosya envanteri olusturuluyor...\n")

extract_toplanti <- function(txt_path) {
  if (!file_exists(txt_path)) return(list(nos = NA_character_, count = 0L, min = NA_integer_, max = NA_integer_, status = "none"))
  txt <- tryCatch(read_file(txt_path), error = function(e) "")
  if (nchar(txt) == 0) return(list(nos = NA_character_, count = 0L, min = NA_integer_, max = NA_integer_, status = "none"))
  ilk5k  <- substr(txt, 1,  5000)
  ilk50k <- substr(txt, 1, 50000)
  ord <- str_match_all(ilk5k,  "([0-9]+)['’\x27‘]?(?:nci|ncı|uncu|üncü|inci)\\s+Toplant")[[1]]
  tko <- str_match_all(ilk50k, "T\\s*:\\s*([0-9]+)")[[1]]
  tno <- str_match_all(ilk5k,  "Toplantı\\s*No\\s*[:\\-]?\\s*([0-9]+)")[[1]]
  all_nos <- sort(unique(c(
    if (nrow(ord) > 0) as.integer(unique(ord[,2])) else integer(0),
    if (nrow(tko) > 0) as.integer(unique(tko[,2])) else integer(0),
    if (nrow(tno) > 0) as.integer(unique(tno[,2])) else integer(0)
  )))
  if (length(all_nos) == 0) return(list(nos = NA_character_, count = 0L, min = NA_integer_, max = NA_integer_, status = "none"))
  list(nos = paste(all_nos, collapse = ","), count = length(all_nos),
       min = min(all_nos), max = max(all_nos),
       status = if (length(all_nos) == 1) "single" else "multiple")
}

build_rows <- function(paths, src, ftype) {
  lapply(paths, function(p) {
    fn <- basename(p)
    ds <- str_extract(fn, "^[0-9]{8}")
    cy <- if (!is.na(ds)) as.integer(substr(ds, 1, 4)) else NA_integer_
    mo <- if (!is.na(ds)) as.integer(substr(ds, 5, 6)) else NA_integer_
    by <- if (!is.na(mo) && !is.na(cy)) { if (mo >= 10L) cy + 1L else cy } else NA_integer_
    tibble(
      source           = src,
      file_type        = ftype,
      file_name        = fn,
      file_path        = p,
      date_str         = ds,
      date_from_fn     = if (!is.na(ds)) as.Date(sprintf("%s-%s-%s", substr(ds,1,4), substr(ds,5,6), substr(ds,7,8))) else as.Date(NA),
      calendar_year    = cy,
      butce_yili_guess = by,
      belge_turu       = case_when(str_detect(fn, "sunum") ~ "sunum", str_detect(fn, "gorusme") ~ "gorusme", TRUE ~ "unknown")
    )
  }) |> bind_rows()
}

pdf_sbb <- list.files(here("data/raw/pdf/sbb"), pattern = "\\.pdf$", full.names = TRUE)
pdf_owa <- list.files(here("data/raw/pdf/owa"), pattern = "\\.pdf$", full.names = TRUE)
txt_sbb <- list.files(here("data/raw/txt/sbb"), pattern = "\\.txt$", full.names = TRUE)
txt_owa <- list.files(here("data/raw/txt/owa"), pattern = "\\.txt$", full.names = TRUE)

all_files <- bind_rows(
  build_rows(pdf_sbb, "sbb", "pdf"), build_rows(pdf_owa, "owa", "pdf"),
  build_rows(txt_sbb, "sbb", "txt"), build_rows(txt_owa, "owa", "txt")
)

pdf_dates_sbb <- str_extract(basename(pdf_sbb), "^[0-9]{8}")
txt_dates_sbb <- str_extract(basename(txt_sbb), "^[0-9]{8}")
pdf_dates_owa <- str_extract(basename(pdf_owa), "^[0-9]{8}")
txt_dates_owa <- str_extract(basename(txt_owa), "^[0-9]{8}")

all_files <- all_files |> mutate(
  has_matching_pdf = case_when(
    file_type == "txt" & source == "sbb" ~ date_str %in% pdf_dates_sbb,
    file_type == "txt" & source == "owa" ~ date_str %in% pdf_dates_owa,
    TRUE ~ TRUE),
  has_matching_txt = case_when(
    file_type == "pdf" & source == "sbb" ~ date_str %in% txt_dates_sbb,
    file_type == "pdf" & source == "owa" ~ date_str %in% txt_dates_owa,
    TRUE ~ TRUE)
)

cat("  TXT dosyalarindan toplanti no cikartiliyor...\n")
txt_files <- all_files |> filter(file_type == "txt")
top_results <- lapply(txt_files$file_path, extract_toplanti)
txt_files <- txt_files |> mutate(
  toplanti_no_list   = sapply(top_results, `[[`, "nos"),
  toplanti_no_count  = sapply(top_results, `[[`, "count"),
  toplanti_no_min    = sapply(top_results, `[[`, "min"),
  toplanti_no_max    = sapply(top_results, `[[`, "max"),
  toplanti_no_status = sapply(top_results, `[[`, "status")
)

pdf_files <- all_files |> filter(file_type == "pdf") |>
  mutate(toplanti_no_list = NA_character_, toplanti_no_count = NA_integer_,
         toplanti_no_min = NA_integer_, toplanti_no_max = NA_integer_,
         toplanti_no_status = NA_character_)

local_inv <- bind_rows(pdf_files, txt_files) |>
  select(-date_str) |> arrange(source, file_type, date_from_fn)

write_csv(local_inv, here("data/processed/pbk_local_file_inventory.csv"))
cat(sprintf("  -> pbk_local_file_inventory.csv: %d satir\n\n", nrow(local_inv)))

# ============================================================
# BOLUM B: WEB KAYNAKLARI
# ============================================================
cat("BOLUM B: Web kaynaklari...\n")

web_records <- list()
scrape_log  <- list()

# --- B1: SBB metadata (mevcut CSV) ---
sbb_meta_path <- here("data/processed/sbb_metadata.csv")
if (file_exists(sbb_meta_path)) {
  sbb_meta <- read_csv(sbb_meta_path, show_col_types = FALSE)
  web_records[["sbb_csv"]] <- sbb_meta |>
    transmute(
      web_source       = "sbb_budget_minutes",
      date             = as.Date(gorusme_tarihi),
      calendar_year    = as.integer(format(as.Date(gorusme_tarihi), "%Y")),
      butce_yili_guess = as.integer(butce_yili),
      toplanti_no      = NA_character_,
      title            = link_metni,
      agenda_text      = NA_character_,
      url              = pdf_url,
      scrape_status    = "ok_from_csv",
      scrape_note      = "sbb_metadata.csv mevcut"
    )
  scrape_log[["sbb_csv"]] <- sprintf("SBB metadata CSV: %d kayit", nrow(sbb_meta))
  cat(sprintf("  B1 SBB metadata CSV: %d kayit\n", nrow(sbb_meta)))
} else {
  scrape_log[["sbb_csv"]] <- "SBB metadata CSV bulunamadi"
  cat("  B1 SBB metadata CSV bulunamadi\n")
}

# --- B2: OWA metadata (mevcut CSV) ---
owa_ids_path <- here("data/processed/owa_butce_ids.csv")
if (file_exists(owa_ids_path)) {
  owa_ids <- read_csv(owa_ids_path, show_col_types = FALSE)
  web_records[["owa_csv"]] <- owa_ids |>
    transmute(
      web_source       = "tbmm_minutes",
      date             = as.Date(tarih),
      calendar_year    = as.integer(format(as.Date(tarih), "%Y")),
      butce_yili_guess = as.integer(butce_yili),
      toplanti_no      = NA_character_,
      title            = baslik,
      agenda_text      = NA_character_,
      url              = kaynak_url,
      scrape_status    = "ok_from_csv",
      scrape_note      = "owa_butce_ids.csv mevcut (butce filtreli)"
    )
  scrape_log[["owa_csv"]] <- sprintf("OWA ids CSV: %d kayit", nrow(owa_ids))
  cat(sprintf("  B2 OWA ids CSV: %d kayit\n", nrow(owa_ids)))
} else {
  scrape_log[["owa_csv"]] <- "OWA ids CSV bulunamadi"
  cat("  B2 OWA ids CSV bulunamadi\n")
}

# --- B3: TBMM OWA - SBB donemi (Donem 26-28) ---
cat("  B3 TBMM sayfasi - Donem 26-28 toplanti listesi cekiliyor...\n")

DONEM_HEDEFLERI <- tribble(
  ~donem, ~yasama_yili, ~butce_yili,
  26L, 1L, 2016L,
  26L, 2L, 2017L,
  26L, 3L, 2018L,
  27L, 1L, 2019L,
  27L, 2L, 2020L,
  27L, 3L, 2021L,
  27L, 4L, 2022L,
  27L, 5L, 2023L,
  28L, 1L, 2024L,
  28L, 2L, 2025L
)

tbmm_rows_all <- vector("list", nrow(DONEM_HEDEFLERI))

for (i in seq_len(nrow(DONEM_HEDEFLERI))) {
  h   <- DONEM_HEDEFLERI[i, ]
  url <- owa_list_url(h$donem, h$yasama_yili)
  cat(sprintf("    Donem %d / YL %d (butce %d)... ", h$donem, h$yasama_yili, h$butce_yili))
  html <- tryCatch({
    request(url) |>
      req_user_agent("TBMM Butce Korpusu Arastirma (R/rvest)") |>
      req_timeout(30) |>
      req_retry(max_tries = 2, backoff = \(j) j * 2) |>
      req_perform() |>
      resp_body_html()
  }, error = function(e) {
    cat(sprintf("HATA: %s\n", conditionMessage(e)))
    NULL
  })
  Sys.sleep(1)

  if (is.null(html)) {
    scrape_log[[paste0("tbmm_d", h$donem, "_yl", h$yasama_yili)]] <-
      sprintf("Donem %d YL %d: erisim basarisiz", h$donem, h$yasama_yili)
    next
  }

  parsed <- tryCatch(parse_owa_tutanak_list(html), error = function(e) {
    tibble(tutanak_id = integer(), baslik = character(), tarih_raw = character())
  })

  if (nrow(parsed) == 0) {
    cat("0 kayit\n")
    scrape_log[[paste0("tbmm_d", h$donem, "_yl", h$yasama_yili)]] <-
      sprintf("Donem %d YL %d: 0 kayit", h$donem, h$yasama_yili)
    next
  }

  parsed <- parsed |>
    mutate(
      donem        = h$donem,
      yasama_yili  = h$yasama_yili,
      butce_yili   = h$butce_yili,
      tarih        = parse_dmy(tarih_raw),
      kaynak_url   = url
    )
  cat(sprintf("%d kayit\n", nrow(parsed)))
  scrape_log[[paste0("tbmm_d", h$donem, "_yl", h$yasama_yili)]] <-
    sprintf("Donem %d YL %d: %d kayit", h$donem, h$yasama_yili, nrow(parsed))
  tbmm_rows_all[[i]] <- parsed
}

tbmm_all <- bind_rows(tbmm_rows_all)
cat(sprintf("  TBMM toplam: %d kayit (Donem 26-28 butce+butce-disi)\n\n", nrow(tbmm_all)))

if (nrow(tbmm_all) > 0) {
  web_records[["tbmm_d2628"]] <- tbmm_all |>
    transmute(
      web_source       = "tbmm_meetings",
      date             = as.Date(tarih),
      calendar_year    = as.integer(format(as.Date(tarih), "%Y")),
      butce_yili_guess = as.integer(butce_yili),
      toplanti_no      = NA_character_,
      title            = baslik,
      agenda_text      = NA_character_,
      url              = kaynak_url,
      scrape_status    = "ok",
      scrape_note      = sprintf("Donem %d YL %d", donem, yasama_yili)
    )
}

# --- B4: SBB sayfasini canli cek (karsılastirma icin) ---
cat("  B4 SBB canli sayfa kontrol...\n")
SBB_URL <- "https://www.sbb.gov.tr/tbmm-plan-ve-butce-komisyonu-butce-tutanaklari/"
sbb_live <- tryCatch({
  pg <- request(SBB_URL) |>
    req_user_agent("TBMM Butce Korpusu Arastirma (R/rvest)") |>
    req_timeout(30) |>
    req_retry(max_tries = 2, backoff = \(j) j * 2) |>
    req_perform() |>
    resp_body_html()
  nodes <- html_elements(pg, "a[href]")
  links <- tibble(
    link_metni = html_text(nodes, trim = TRUE),
    href = html_attr(nodes, "href")
  ) |> filter(grepl("wp-content/uploads", href, fixed = TRUE),
              grepl("\\.pdf$", href, ignore.case = TRUE))
  Sys.sleep(1)
  links
}, error = function(e) {
  cat(sprintf("    SBB canli sayfa hatasi: %s\n", conditionMessage(e)))
  NULL
})

if (!is.null(sbb_live)) {
  cat(sprintf("  SBB canli sayfa: %d PDF linki bulundu\n", nrow(sbb_live)))
  sbb_online_count <- nrow(sbb_live)
  sbb_local_count  <- length(pdf_sbb)
  cat(sprintf("  SBB online: %d, yerel: %d, fark: %d\n",
              sbb_online_count, sbb_local_count, sbb_online_count - sbb_local_count))
  scrape_log[["sbb_live"]] <- sprintf("SBB canli: %d PDF, yerel: %d, fark: %+d",
                                       sbb_online_count, sbb_local_count,
                                       sbb_online_count - sbb_local_count)
} else {
  scrape_log[["sbb_live"]] <- "SBB canli sayfa erisim basarisiz"
}

web_df <- bind_rows(web_records)
write_csv(web_df, here("data/processed/pbk_web_toplanti_evreni_raw.csv"))
cat(sprintf("\n  -> pbk_web_toplanti_evreni_raw.csv: %d satir\n\n", nrow(web_df)))

# ============================================================
# BOLUM C: BUTCE / BUTCE-DISI SINIFLANDIRMASI
# ============================================================
cat("BOLUM C: Siniflandirma...\n")

classify_rows <- function(df) {
  res <- lapply(df$title, classify_text)
  df |> mutate(
    is_budget_related          = sapply(res, `[[`, "is_budget"),
    budget_related_reason      = sapply(res, `[[`, "budget_reason"),
    non_budget_reason          = sapply(res, `[[`, "non_budget_reason"),
    classification_confidence  = sapply(res, `[[`, "confidence"),
    needs_manual_review        = sapply(res, `[[`, "needs_review")
  )
}

# SBB: tum dosyalar butce ile ilgili (sayfa adi "Butce Tutanaklari"),
# ancak title kontrol edelim
sbb_web <- web_df |> filter(web_source == "sbb_budget_minutes")
owa_web <- web_df |> filter(web_source == "tbmm_minutes")
tbmm_web <- web_df |> filter(web_source == "tbmm_meetings")

# SBB icin title keyword bulamazsa "sbb_page_default" ile butce = TRUE yap
sbb_classified <- classify_rows(sbb_web) |>
  mutate(
    is_budget_related = if_else(is.na(is_budget_related), TRUE, is_budget_related),
    budget_related_reason = if_else(is.na(budget_related_reason),
                                     "SBB butce tutanaklari sayfasindan (sayfa basligi garantisi)",
                                     budget_related_reason),
    classification_confidence = if_else(classification_confidence == "low", "medium", classification_confidence)
  )

# OWA icin is_butce filtresi zaten uygulanmis
owa_classified <- owa_web |>
  mutate(
    is_budget_related         = TRUE,
    budget_related_reason     = "owa_butce_ids.csv is_butce filtreli",
    non_budget_reason         = NA_character_,
    classification_confidence = "high",
    needs_manual_review       = FALSE
  )

# TBMM icin keyword siniflandirma
tbmm_classified <- if (nrow(tbmm_web) > 0) classify_rows(tbmm_web) else tbmm_web |>
  mutate(is_budget_related = logical(), budget_related_reason = character(),
         non_budget_reason = character(), classification_confidence = character(),
         needs_manual_review = logical())

classified_all <- bind_rows(sbb_classified, owa_classified, tbmm_classified)
write_csv(classified_all, here("data/processed/pbk_toplanti_evreni_classified.csv"))
cat(sprintf("  -> pbk_toplanti_evreni_classified.csv: %d satir\n", nrow(classified_all)))
cat(sprintf("     Butce ilgili: %d | Butce disi: %d | NA: %d\n",
    sum(classified_all$is_budget_related == TRUE,  na.rm = TRUE),
    sum(classified_all$is_budget_related == FALSE, na.rm = TRUE),
    sum(is.na(classified_all$is_budget_related))))
cat("\n")

# ============================================================
# BOLUM D: YEREL KORPUS vs BEKLENEN TOPLANTI KARSILASTIRMASI
# ============================================================
cat("BOLUM D: Kapsama karsilastirmasi...\n")

# "Beklenen" = butce ile ilgili web kayitlari
expected_budget <- classified_all |>
  filter(is_budget_related == TRUE | is.na(is_budget_related)) |>
  filter(!is.na(date)) |>
  arrange(date)

# Yerel dosyalar: SBB + OWA (PDF, tarih bazli benzersiz gunler)
local_dates_sbb <- local_inv |>
  filter(source == "sbb", file_type == "pdf", !is.na(date_from_fn)) |>
  pull(date_from_fn)
local_dates_owa <- local_inv |>
  filter(source == "owa", file_type == "pdf", !is.na(date_from_fn)) |>
  pull(date_from_fn)
local_dates_all <- unique(c(local_dates_sbb, local_dates_owa))

match_local <- function(date_val) {
  if (is.na(date_val)) return(list(pdf = FALSE, txt = FALSE, src = "none", files = NA_character_))
  sbb_p <- date_val %in% local_dates_sbb
  owa_p <- date_val %in% local_dates_owa
  pdf_e <- sbb_p | owa_p
  src <- case_when(sbb_p & owa_p ~ "both", sbb_p ~ "sbb", owa_p ~ "owa", TRUE ~ "none")
  # TXT
  txt_d_sbb <- local_inv |> filter(source == "sbb", file_type == "txt", !is.na(date_from_fn)) |> pull(date_from_fn)
  txt_d_owa <- local_inv |> filter(source == "owa", file_type == "txt", !is.na(date_from_fn)) |> pull(date_from_fn)
  txt_e <- (date_val %in% txt_d_sbb) | (date_val %in% txt_d_owa)
  files <- local_inv |>
    filter(file_type == "pdf", date_from_fn == date_val) |>
    pull(file_name) |> paste(collapse = "; ")
  list(pdf = pdf_e, txt = txt_e, src = src, files = if (nchar(files) == 0) NA_character_ else files)
}

cat("  Eslestirme yapiliyor...\n")
match_results <- lapply(expected_budget$date, match_local)

comparison <- expected_budget |>
  mutate(
    local_pdf_exists    = sapply(match_results, `[[`, "pdf"),
    local_txt_exists    = sapply(match_results, `[[`, "txt"),
    local_source        = sapply(match_results, `[[`, "src"),
    matched_local_files = sapply(match_results, `[[`, "files"),
    match_confidence    = case_when(
      local_pdf_exists & local_txt_exists ~ "high",
      local_pdf_exists & !local_txt_exists ~ "medium",
      !local_pdf_exists ~ "none",
      TRUE ~ "low"
    ),
    coverage_status = case_when(
      local_pdf_exists                                         ~ "covered",
      !local_pdf_exists & is_budget_related == TRUE  & classification_confidence == "high" ~ "missing_budget_related",
      !local_pdf_exists & is.na(is_budget_related)            ~ "uncertain_manual_review",
      !local_pdf_exists & classification_confidence == "low"  ~ "uncertain_manual_review",
      TRUE ~ "covered"
    ),
    coverage_note = case_when(
      coverage_status == "covered"                ~ "Yerel korpusta mevcut",
      coverage_status == "missing_budget_related" ~ paste0("Eksik; web kaynagi: ", web_source),
      coverage_status == "uncertain_manual_review"~ "Siniflandirma belirsiz; manuel kontrol",
      TRUE ~ NA_character_
    )
  )

# Butce ile ilgili olup korpusta olmayan
missing_budget <- comparison |>
  filter(coverage_status == "missing_budget_related")

# Butce disi toplantılar
non_budget <- classified_all |> filter(is_budget_related == FALSE)

# Manuel kontrol listesi
manual_review <- comparison |>
  filter(coverage_status == "uncertain_manual_review" | needs_manual_review == TRUE) |>
  head(50)

write_csv(comparison, here("data/processed/pbk_butce_kapsama_karsilastirma.csv"))
write_csv(
  comparison |> filter(is_budget_related == TRUE),
  here("data/processed/pbk_butce_toplantilari_beklenen.csv")
)
write_csv(non_budget, here("data/processed/pbk_butce_disi_toplantilar.csv"))
write_csv(manual_review, here("data/processed/pbk_manual_review_list.csv"))

cat(sprintf("  Beklenen butce toplantilari: %d\n", nrow(comparison |> filter(is_budget_related == TRUE))))
cat(sprintf("  Kapsanan (local_pdf_exists): %d\n", sum(comparison$local_pdf_exists, na.rm=TRUE)))
cat(sprintf("  Eksik butce adayi:           %d\n", nrow(missing_budget)))
cat(sprintf("  Butce disi:                  %d\n", nrow(non_budget)))
cat(sprintf("  Manuel kontrol:              %d\n", nrow(manual_review)))
cat("\n")

# ============================================================
# BOLUM E: TOPLANTI NO BOSLUKLARINI YENIDEN YORUMLA
# ============================================================
cat("BOLUM E: Ardisiklik bosluklar yeniden yorumlanıyor...\n")

ardisiklik_path <- here("data/processed/sbb_ardisiklik_v2.csv")
envanteri_path  <- here("data/processed/sbb_toplanti_envanteri.csv")

yorumlu_rows <- list()

if (file_exists(ardisiklik_path) && file_exists(envanteri_path)) {
  ardisik <- read_csv(ardisiklik_path, show_col_types = FALSE,
                      col_types = cols(eksik_nolar = col_character(), butce_yili = col_integer()))
  envanter <- read_csv(envanteri_path, show_col_types = FALSE,
                       col_types = cols(butce_yili = col_integer(), tarih = col_character()))

  for (i in seq_len(nrow(ardisik))) {
    row <- ardisik[i, ]
    if (!row$eksik_var || is.na(row$eksik_nolar) || nchar(row$eksik_nolar) == 0) next
    eksik_nos <- as.integer(strsplit(row$eksik_nolar, ",")[[1]])

    for (tno in eksik_nos) {
      # Bu toplanti no bizde olan komsu dosyalardan tarih araligini cikar
      yil_env <- envanter |> filter(butce_yili == row$butce_yili, toplanti_no_sayisi > 0)
      onceki <- yil_env |> filter(max_t < tno) |> slice_tail(n = 1)
      sonraki <- yil_env |> filter(min_t > tno) |> slice_head(n = 1)
      tarih_aralik <- if (nrow(onceki) > 0 && nrow(sonraki) > 0) {
        sprintf("%s - %s", onceki$tarih, sonraki$tarih)
      } else if (nrow(onceki) > 0) {
        sprintf("> %s", onceki$tarih)
      } else if (nrow(sonraki) > 0) {
        sprintf("< %s", sonraki$tarih)
      } else {
        NA_character_
      }

      # TBMM kayitlarinda bu tarih araliginda ne var?
      tbmm_check <- if (nrow(tbmm_all) > 0 && nrow(onceki) > 0 && nrow(sonraki) > 0) {
        d_from <- as.Date(onceki$tarih, format = "%Y%m%d")
        d_to   <- as.Date(sonraki$tarih, format = "%Y%m%d")
        tbmm_all |>
          filter(!is.na(tarih), as.Date(tarih) > d_from, as.Date(tarih) < d_to) |>
          select(tarih, baslik) |>
          mutate(text = sprintf("%s: %s", tarih, baslik)) |>
          pull(text) |> paste(collapse = " | ")
      } else NA_character_

      # Siniflandirma
      cl_result <- classify_text(if (!is.na(tbmm_check)) tbmm_check else "")
      yorum <- case_when(
        !is.na(tbmm_check) && nchar(tbmm_check) > 0 && cl_result$is_budget == FALSE ~
          "not_budget_related",
        !is.na(tbmm_check) && nchar(tbmm_check) > 0 && cl_result$is_budget == TRUE ~
          "missing_budget_related",
        TRUE ~ "uncertain_manual_review"
      )

      yorumlu_rows[[length(yorumlu_rows) + 1]] <- tibble(
        butce_yili     = row$butce_yili,
        eksik_toplanti_no = tno,
        tarih_aralik   = tarih_aralik,
        tbmm_bulgu     = if (!is.na(tbmm_check) && nchar(tbmm_check) > 0) tbmm_check else NA_character_,
        yorum          = yorum,
        siniflandirma_guveni = cl_result$confidence
      )
    }
  }
}

yorumlu_df <- bind_rows(yorumlu_rows)
if (nrow(yorumlu_df) == 0) {
  yorumlu_df <- tibble(butce_yili = integer(), eksik_toplanti_no = integer(),
                        tarih_aralik = character(), tbmm_bulgu = character(),
                        yorum = character(), siniflandirma_guveni = character())
}
write_csv(yorumlu_df, here("data/processed/pbk_toplanti_bosluklari_yorumlu.csv"))
cat(sprintf("  -> pbk_toplanti_bosluklari_yorumlu.csv: %d bosluk yorumlandi\n\n", nrow(yorumlu_df)))

if (nrow(yorumlu_df) > 0) {
  print(yorumlu_df |> select(butce_yili, eksik_toplanti_no, tarih_aralik, yorum, tbmm_bulgu))
}

# ============================================================
# BOLUM F: OZET TABLOLAR
# ============================================================
cat("BOLUM F: Ozet tablolar...\n")

# F1: Butce yilina gore yerel dosya sayisi
ozet_yerel <- local_inv |>
  filter(file_type == "pdf", !is.na(butce_yili_guess)) |>
  group_by(butce_yili = butce_yili_guess) |>
  summarise(
    n_local_pdf = n(),
    n_unique_dates_local = n_distinct(date_from_fn, na.rm = TRUE),
    .groups = "drop"
  ) |>
  left_join(
    local_inv |> filter(file_type == "txt", !is.na(butce_yili_guess)) |>
      group_by(butce_yili = butce_yili_guess) |>
      summarise(n_local_txt = n(), n_unique_toplanti_no_local = sum(toplanti_no_count, na.rm = TRUE), .groups = "drop"),
    by = "butce_yili"
  ) |>
  arrange(butce_yili)

# F2: Kapsama ozeti (beklenen vs kapsanan)
ozet_kapsama <- comparison |>
  filter(is_budget_related == TRUE) |>
  group_by(butce_yili = butce_yili_guess) |>
  summarise(
    n_expected_budget_meetings = n(),
    n_covered                  = sum(coverage_status == "covered", na.rm = TRUE),
    n_missing_budget_related   = sum(coverage_status == "missing_budget_related", na.rm = TRUE),
    n_uncertain_manual_review  = sum(coverage_status == "uncertain_manual_review", na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(coverage_rate = round(n_covered / n_expected_budget_meetings, 3)) |>
  arrange(butce_yili)

# F3: Butce disi toplantılar
ozet_butce_disi <- if (nrow(non_budget) > 0) {
  non_budget |>
    group_by(butce_yili = butce_yili_guess) |>
    summarise(
      n_non_budget_meetings = n(),
      examples = paste(head(title, 3), collapse = " | "),
      .groups = "drop"
    ) |> arrange(butce_yili)
} else {
  tibble(butce_yili = integer(), n_non_budget_meetings = integer(), examples = character())
}

ozet_yil <- ozet_yerel |>
  left_join(ozet_kapsama, by = "butce_yili") |>
  left_join(ozet_butce_disi |> select(butce_yili, n_non_budget_meetings), by = "butce_yili") |>
  mutate(across(where(is.integer), ~replace_na(., 0L)))

write_csv(ozet_yil, here("data/processed/pbk_kapsama_ozet_yil.csv"))
cat(sprintf("  -> pbk_kapsama_ozet_yil.csv: %d satir\n\n", nrow(ozet_yil)))
options(width = 120)
print(ozet_yil, n = Inf)

# ============================================================
# BOLUM G: MARKDOWN RAPOR
# ============================================================
cat("\nBOLUM G: Markdown rapor yaziliyor...\n")

web_sources_str <- paste(
  "- **SBB metadata CSV**: sbb_metadata.csv mevcut",
  if (!is.null(sbb_live)) sprintf("- **SBB canli sayfa**: %d PDF linki bulundu (yerel: %d)", nrow(sbb_live), length(pdf_sbb)) else "- **SBB canli sayfa**: erişim başarısız",
  "- **OWA ids CSV**: owa_butce_ids.csv mevcut (98 kayit, butce filtreli)",
  sprintf("- **TBMM Donem 26-28 sayfasi**: %d kayit cekildi", nrow(tbmm_all)),
  sep = "\n"
)

ardisiklik_ozet <- if (file_exists(ardisiklik_path)) {
  ardisik <- read_csv(ardisiklik_path, show_col_types = FALSE)
  ardisik |>
    mutate(satir = sprintf("| %d | %d-%d | %d | %s | %s |",
                            butce_yili, min_t, max_t, farkli_toplanti_sayisi,
                            if_else(eksik_var, "**EKSIK**", "Tam"),
                            if_else(eksik_var & !is.na(eksik_nolar) & nchar(eksik_nolar) > 0,
                                    eksik_nolar, "-"))) |>
    pull(satir) |> paste(collapse = "\n")
} else "(ardisiklik CSV bulunamadi)"

missing_tablo <- if (nrow(missing_budget) > 0) {
  missing_budget |>
    mutate(satir = sprintf("| %s | %s | %s | %s | %s |",
                            format(date, "%Y-%m-%d"),
                            coalesce(as.character(butce_yili_guess), "?"),
                            coalesce(title, "-"),
                            web_source,
                            coalesce(coverage_note, "-"))) |>
    pull(satir) |> paste(collapse = "\n") |>
    paste("| Tarih | Butce Yili | Baslik | Kaynak | Not |\n|---|---|---|---|---|", ... = _, sep = "\n")
} else "_Eksik butce toplantisi adayi bulunamadi._"

yorumlu_tablo <- if (nrow(yorumlu_df) > 0) {
  yorumlu_df |>
    mutate(satir = sprintf("| %d | T.%d | %s | %s | %s |",
                            butce_yili, eksik_toplanti_no,
                            coalesce(tarih_aralik, "?"),
                            yorum,
                            coalesce(substr(tbmm_bulgu, 1, 80), "TBMM verisi yok"))) |>
    pull(satir) |> paste(collapse = "\n") |>
    paste("| Yil | Toplanti No | Tarih Aralik | Yorum | TBMM Bulgu |\n|---|---|---|---|---|", ... = _, sep = "\n")
} else "_Ardisiklik boslugu yorumu uretilmedi (TBMM verisi yeterli degil veya bosluk yok)._"

n_exp <- sum(comparison$is_budget_related == TRUE, na.rm = TRUE)
n_cov <- sum(comparison$local_pdf_exists & comparison$is_budget_related == TRUE, na.rm = TRUE)
cov_pct <- if (n_exp > 0) round(100 * n_cov / n_exp, 1) else NA_real_

rapor <- sprintf(
'# Asama 5a.5 — PBK Butce Toplantisi Evreni Raporu

**Tarih:** %s
**Script:** scripts/18_kapsama_analizi.R

---

## 1. Amac

Bu sprintin amaci: PBK butce toplantisi evrenini yerel korpusla karsilastirmak ve kapsama dogrulamasi yapmak.

Toplanti numarasi ardisikligi (T.5 eksik gibi) dogrudan butce tutanagi eksikligi anlamina gelmez.
Bazi PBK toplantilari butce sureci icerisinde olmakla birlikte butce disi gundemli olabilir
(Kalkinma Plani, kanun teklifi, Merkez Bankasi sunumu vb.). Bu sprintte her bosluk tarih ve gundem
uzerinden yeniden degerlendirilmistir.

---

## 2. Kullanilan Kaynaklar

%s

**Scrape log:**
%s

---

## 3. Uretilen Dosyalar

| Dosya | Satir | Aciklama |
|---|---|---|
| pbk_local_file_inventory.csv | %d | Tum yerel PDF/TXT dosyalari |
| pbk_web_toplanti_evreni_raw.csv | %d | Ham web kayitlari |
| pbk_toplanti_evreni_classified.csv | %d | Siniflandirilmis web kayitlari |
| pbk_butce_kapsama_karsilastirma.csv | %d | Yerel vs beklenen karsilastirma |
| pbk_butce_toplantilari_beklenen.csv | %d | Beklenen butce toplantilari |
| pbk_butce_disi_toplantilar.csv | %d | Butce disi toplantılar |
| pbk_toplanti_bosluklari_yorumlu.csv | %d | Ardisiklik boslukları yorumlu |
| pbk_kapsama_ozet_yil.csv | %d | Yil bazli ozet |
| pbk_manual_review_list.csv | %d | Manuel kontrol listesi |

---

## 4. Yerel Korpus Ozeti

- **SBB (2016-2025):** %d PDF, %d TXT
- **OWA (2009-2015):** %d PDF, %d TXT
- **Toplam:** %d PDF, %d TXT

---

## 5. Web Toplanti Evreni Ozeti

- SBB sayfasindan: %d butce PDF linki
- OWA/TBMM gecmisten: %d butce tutanagi
- TBMM Donem 26-28 sayfasindan: %d toplanti (butce+butce-disi)
- Siniflandirma: Butce ilgili=%d, Butce disi=%d, NA=%d

---

## 6. Kapsama Sonucu

| Butce Yili | Yerel PDF | Beklenen Butce Top. | Kapsanan | Eksik | Belirsiz | Kapsama Orani |
|---|---|---|---|---|---|---|
%s

**Genel kapsama:** %d / %d (%.1f%%%)

---

## 7. Eksik Butce Toplantisi Adaylari

%s

---

## 8. Butce Disi Oldugu Icin Eksik Sayilmamasi Gerekenler

%s

---

## 9. Manuel Kontrol Listesi

%d kayit manuel kontrol gerektiriyor (pbk_manual_review_list.csv icerisinde).

---

## 10. Sonuc ve Oneri

- **Korpus butce toplantilari bakimindan tam mi?** %s
- **Hangi yillar/tarihler sorunlu?** %s
- **Bakanlik kapsama dogrulamasina gecmek icin yeterli guven var mi?** %s
- **Asama 5b oncesi kritik manuel kontrol gereken kayit:** %d kayit
',
  format(Sys.time(), "%Y-%m-%d"),
  web_sources_str,
  paste(unlist(scrape_log), collapse = "\n"),
  nrow(local_inv),
  nrow(web_df),
  nrow(classified_all),
  nrow(comparison),
  nrow(comparison |> filter(is_budget_related == TRUE)),
  nrow(non_budget),
  nrow(yorumlu_df),
  nrow(ozet_yil),
  nrow(manual_review),
  sum(local_inv$source == "sbb" & local_inv$file_type == "pdf"),
  sum(local_inv$source == "sbb" & local_inv$file_type == "txt"),
  sum(local_inv$source == "owa" & local_inv$file_type == "pdf"),
  sum(local_inv$source == "owa" & local_inv$file_type == "txt"),
  sum(local_inv$file_type == "pdf"),
  sum(local_inv$file_type == "txt"),
  if (exists("sbb_meta")) nrow(sbb_meta) else 0L,
  if (exists("owa_ids")) nrow(owa_ids) else 0L,
  nrow(tbmm_all),
  sum(classified_all$is_budget_related == TRUE,  na.rm = TRUE),
  sum(classified_all$is_budget_related == FALSE, na.rm = TRUE),
  sum(is.na(classified_all$is_budget_related)),
  {
    if (nrow(ozet_yil) > 0) {
      ozet_yil |>
        mutate(satir = sprintf("| %d | %d | %d | %d | %d | %d | %.0f%% |",
                                butce_yili,
                                coalesce(n_local_pdf, 0L),
                                coalesce(n_expected_budget_meetings, 0L),
                                coalesce(n_covered, 0L),
                                coalesce(n_missing_budget_related, 0L),
                                coalesce(n_uncertain_manual_review, 0L),
                                coalesce(coverage_rate, 0) * 100)) |>
        pull(satir) |> paste(collapse = "\n")
    } else "(tablo uretilmedi)"
  },
  n_cov, n_exp, coalesce(cov_pct, 0),
  missing_tablo,
  yorumlu_tablo,
  nrow(manual_review),
  if (cov_pct >= 95) "Evet, %95+ kapsama" else sprintf("Hayir/Belirsiz - %.1f%% kapsama", coalesce(cov_pct, 0)),
  if (nrow(missing_budget) > 0) paste(unique(missing_budget$date), collapse = ", ") else "Belirgin sorun yok",
  if (nrow(manual_review) < 10) "Evet, az belirsizlik" else "Hayir, manuel kontrol gerekli",
  nrow(manual_review)
)

writeLines(rapor, here("reports/05a5_pbk_toplanti_evreni_raporu.md"), useBytes = FALSE)
cat("  -> reports/05a5_pbk_toplanti_evreni_raporu.md\n\n")

# ============================================================
# BOLUM H: CHATGPT OZETI
# ============================================================
cat("\n")
cat(strrep("=", 65), "\n")
cat("ASAMA 5a.5 OZETI — PBK BUTCE TOPLANTISI EVRENI\n")
cat(strrep("=", 65), "\n")
cat(sprintf("1.  Calistirilan script: scripts/18_kapsama_analizi.R\n"))
cat(sprintf("2.  Uretilen dosyalar: pbk_local_file_inventory.csv, pbk_web_toplanti_evreni_raw.csv,
    pbk_toplanti_evreni_classified.csv, pbk_butce_kapsama_karsilastirma.csv,
    pbk_butce_toplantilari_beklenen.csv, pbk_butce_disi_toplantilar.csv,
    pbk_toplanti_bosluklari_yorumlu.csv, pbk_kapsama_ozet_yil.csv,
    pbk_manual_review_list.csv, 05a5_pbk_toplanti_evreni_raporu.md\n"))
cat(sprintf("3.  Yerel korpus toplam PDF: %d (%d SBB + %d OWA), TXT: %d\n",
    sum(local_inv$file_type == "pdf"), length(pdf_sbb), length(pdf_owa),
    sum(local_inv$file_type == "txt")))
cat(sprintf("4.  Webden bulunan PBK toplantisi sayisi: %d (SBB CSV=%d, OWA CSV=%d, TBMM=%d)\n",
    nrow(web_df), if(exists("sbb_meta")) nrow(sbb_meta) else 0,
    if(exists("owa_ids")) nrow(owa_ids) else 0, nrow(tbmm_all)))
cat(sprintf("5.  Butce ile ilgili siniflandirilmis: %d\n", sum(classified_all$is_budget_related == TRUE, na.rm=TRUE)))
cat(sprintf("6.  Butce disi siniflandirilmis: %d\n",      sum(classified_all$is_budget_related == FALSE, na.rm=TRUE)))
cat(sprintf("7.  Yerel korpusta kapsanan butce toplantisi: %d / %d (%.1f%%)\n",
    n_cov, n_exp, coalesce(cov_pct, 0)))
cat(sprintf("8.  Eksik butce toplantisi adaylari: %d\n", nrow(missing_budget)))
if (nrow(missing_budget) > 0) {
  for (r in seq_len(min(5, nrow(missing_budget)))) {
    cat(sprintf("    - %s | %s | %s\n", missing_budget$date[r], missing_budget$title[r], missing_budget$web_source[r]))
  }
}
cat(sprintf("9.  Manuel kontrol gerektiren kayitlar: %d\n", nrow(manual_review)))
cat(sprintf("10. 2023 Ekim ornegi:\n"))
ekim2023_tbmm <- if (nrow(tbmm_all) > 0) {
  tbmm_all |>
    filter(!is.na(tarih), format(tarih, "%Y-%m") == "2023-10") |>
    mutate(satir = sprintf("    - %s: %s", tarih, baslik)) |>
    pull(satir) |> paste(collapse = "\n")
} else "    TBMM verisi alinamadi; 2023-10-23 ve 2023-10-24 yerel dosya yok (onceki analiz)."
cat(ekim2023_tbmm, "\n")
cat(sprintf("11. Ana sonuc: %s\n",
    if (coalesce(cov_pct, 0) >= 95) "Korpus yuksek kapsama oraninda (%95+). Beklenen butce toplantilari buyuk cogunlukla mevcut."
    else sprintf("Kapsama %.1f%%. Eksik adaylar veya belirsizlikler var.", coalesce(cov_pct, 0))))
cat(sprintf("12. Asama 5b'ye gecilebilir mi? %s\n",
    if (nrow(missing_budget) == 0 && nrow(manual_review) < 10) "Evet — eksik butce adayi yok, az belirsizlik."
    else "Manuel kontrol yapildiktan sonra."))
cat(sprintf("13. Riskler/sinirliliklar:\n"))
cat("    - TBMM Donem 26-28 toplanti baslikları boş ise sınıflandırma NA kalır.\n")
cat("    - SBB sayfasında her PDF butce ilişkili kabul edildi (sayfa başlığı garantisi).\n")
cat("    - OWA dönemi butce dışı toplantılar mevcut envantere dahil değil.\n")
cat(strrep("=", 65), "\n")

cat("\nBitis:", format(Sys.time()), "\n")
