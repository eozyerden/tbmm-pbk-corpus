# TBMM milletvekili listesi — dönem 23-28 scraper
# Kaynak : https://www5.tbmm.gov.tr (Oracle OWA sistemi)
# Çıktı  : data/raw/html/tbmm_mv/donem_XX.html (yedek)
#           data/processed/mv_listesi.csv
#           data/processed/mv_metadata.parquet

suppressPackageStartupMessages({
  library(httr2)
  library(rvest)
  library(xml2)
  library(dplyr)
  library(stringr)
  library(here)
  library(fs)
  library(readr)
  library(arrow)
  library(tibble)
})

# ── Dizinler ve log ────────────────────────────────────────────────────────────
html_dir <- here("data", "raw", "html", "tbmm_mv")
dir_create(html_dir, recurse = TRUE)
dir_create(here("logs"), recurse = TRUE)
dir_create(here("data", "processed"), recurse = TRUE)

log_path <- here("logs", sprintf("tbmm_mv_scrape_%s.log",
                                  format(Sys.time(), "%Y%m%d_%H%M%S")))

log_msg <- function(...) {
  msg <- paste0("[", format(Sys.time(), "%H:%M:%S"), "] ", paste(...))
  cat(msg, "\n")
  write(msg, log_path, append = TRUE)
}

log_msg("=== TBMM MV Scrape basliyor ===")

# ── Fetch (retry + exponential backoff) ───────────────────────────────────────
fetch_with_retry <- function(url, max_tries = 3) {
  for (attempt in seq_len(max_tries)) {
    result <- tryCatch({
      resp <- request(url) |>
        req_headers(
          "User-Agent" = "Mozilla/5.0 (compatible; academic-research-bot/1.0)"
        ) |>
        req_timeout(30) |>
        req_perform()
      if (resp_status(resp) == 200) {
        return(resp_body_string(resp))
      }
      log_msg(sprintf("HTTP %d, deneme %d/%d", resp_status(resp), attempt, max_tries))
      NULL
    }, error = function(e) {
      log_msg(sprintf("Hata (deneme %d/%d): %s", attempt, max_tries, conditionMessage(e)))
      NULL
    })
    if (!is.null(result)) return(result)
    if (attempt < max_tries) {
      wait <- 2^attempt
      log_msg(sprintf("  %d sn bekleniyor...", wait))
      Sys.sleep(wait)
    }
  }
  stop("Tum denemeler basarisiz: ", url)
}

# ── HTML parse: bir dönemin mv listesi ────────────────────────────────────────
parse_donem_html <- function(html_content, donem, url) {
  page <- tryCatch(read_html(html_content, encoding = "UTF-8"),
                   error = function(e) read_html(html_content))

  # Tüm <tr> satırlarını al
  all_rows <- html_nodes(page, "tr")
  if (length(all_rows) == 0) {
    # Tablo yok — düz link listesi dene
    log_msg(sprintf("  Donem %d: tablo bulunamadi, link tarama moduna geciyor", donem))
    return(parse_fallback(page, donem, url))
  }

  il_current <- NA_character_
  records    <- list()

  # Türkiye il adları (kısmi liste — eşleşmeye yardımcı)
  il_pattern <- paste0(
    "^(ADANA|ADIYAMAN|AFYONKARAHİSAR|AĞRI|AKSARAY|AMASYA|ANKARA|ANTALYA|",
    "ARDAHAN|ARTVİN|AYDIN|BALIKESİR|BARTIN|BATMAN|BAYBURT|BİLECİK|BİNGÖL|",
    "BİTLİS|BOLU|BURDUR|BURSA|ÇANAKKALE|ÇANKIRI|ÇORUM|DENİZLİ|DİYARBAKIR|",
    "DÜZCE|EDİRNE|ELAZIĞ|ERZİNCAN|ERZURUM|ESKİŞEHİR|GAZİANTEP|GİRESUN|",
    "GÜMÜŞHANE|HAKKARİ|HATAY|IĞDIR|ISPARTA|İSTANBUL|İZMİR|KAHRAMANMARAŞ|",
    "KARABÜK|KARAMAN|KARS|KASTAMONU|KAYSERİ|KIRIKKALE|KIRKLARELİ|KIRŞEHİR|",
    "KİLİS|KOCAELİ|KONYA|KÜTAHYA|MALATYA|MANİSA|MARDİN|MERSİN|MUĞLA|MUŞ|",
    "NEVŞEHİR|NİĞDE|ORDU|OSMANİYE|RİZE|SAKARYA|SAMSUN|SİİRT|SİNOP|SİVAS|",
    "ŞANLIURFA|ŞIRNAK|TEKİRDAĞ|TOKAT|TRABZON|TUNCELİ|UŞAK|VAN|YALOVA|",
    "YOZGAT|ZONGULDAK)$"
  )

  for (row in all_rows) {
    cells      <- html_nodes(row, "td, th")
    mv_links   <- html_nodes(row, "a[href*='p_sicil']")
    row_text   <- str_trim(html_text(row))

    if (length(mv_links) == 0) {
      # İl başlığı satırı mı?
      if (length(cells) > 0) {
        candidate <- str_trim(html_text(cells[[1]]))
        # Bold içindeki metni de dene
        bold_text <- html_nodes(cells[[1]], "b, strong") |>
          html_text(trim = TRUE)
        if (length(bold_text) > 0) candidate <- bold_text[[1]]

        candidate <- str_to_upper(str_remove_all(candidate, "[^A-ZÇĞİÖŞÜa-zçğişöü ]"))
        candidate <- str_trim(candidate)

        if (str_detect(candidate, il_pattern)) {
          il_current <- candidate
        }
      }
      next
    }

    # Mv satırı: her linki işle
    for (lnk in mv_links) {
      href     <- html_attr(lnk, "href")
      isim_ham <- str_trim(html_text(lnk))
      sicil    <- suppressWarnings(
        as.integer(str_extract(href, "(?<=p_sicil=)\\d+"))
      )

      if (is.na(sicil) || nchar(isim_ham) < 2) next

      # Parti: 2. hücrede veya linkin yanındaki metin
      parti <- NA_character_
      if (length(cells) >= 2) {
        parti <- str_trim(html_text(cells[[2]]))
        # Eğer 2. hücre de link içeriyorsa 3. hücreyi dene
        if (str_detect(parti, "(?i)p_sicil") || nchar(parti) == 0) {
          if (length(cells) >= 3) parti <- str_trim(html_text(cells[[3]]))
        }
      }

      # Parti temizlik: çok uzun string parti değil
      if (!is.na(parti) && nchar(parti) > 60) parti <- NA_character_

      records[[length(records) + 1]] <- tibble(
        isim_ham = isim_ham,
        sicil    = sicil,
        il       = il_current,
        parti    = parti
      )
    }
  }

  if (length(records) == 0) return(parse_fallback(page, donem, url))

  result <- bind_rows(records)
  log_msg(sprintf("  Donem %d: %d kayit parse edildi", donem, nrow(result)))
  result
}

# ── Fallback: sadece link tarama (il ataması yok) ─────────────────────────────
parse_fallback <- function(page, donem, url) {
  mv_links <- html_nodes(page, "a[href*='p_sicil']")
  if (length(mv_links) == 0) {
    log_msg(sprintf("  Donem %d: HICBIR MV LINKI BULUNAMADI", donem))
    return(tibble())
  }
  tibble(
    isim_ham = html_text(mv_links, trim = TRUE),
    sicil    = suppressWarnings(
      as.integer(str_extract(html_attr(mv_links, "href"), "(?<=p_sicil=)\\d+"))
    ),
    il       = NA_character_,
    parti    = NA_character_
  ) |> filter(!is.na(sicil), nchar(isim_ham) > 1)
}

# ── Ana döngü ─────────────────────────────────────────────────────────────────
donemler    <- 23:28
all_results <- list()

for (donem in donemler) {
  html_path <- file.path(html_dir, sprintf("donem_%d.html", donem))
  url <- sprintf(
    "https://www5.tbmm.gov.tr/develop/owa/milletvekillerimiz_sd.mv_liste_eskiler?p_donem_kodu=%d",
    donem
  )

  # Resume
  if (file_exists(html_path) && file_size(html_path) > 1000) {
    log_msg(sprintf("Donem %d: mevcut HTML okunuyor", donem))
    html_content <- read_file(html_path)
  } else {
    log_msg(sprintf("Donem %d: fetch ediliyor — %s", donem, url))
    html_content <- fetch_with_retry(url)
    write_file(html_content, html_path)
    log_msg(sprintf("  HTML kaydedildi: %d byte", nchar(html_content, type = "bytes")))
    Sys.sleep(2)
  }

  parsed <- parse_donem_html(html_content, donem, url)

  if (nrow(parsed) > 0) {
    parsed$donem        <- as.integer(donem)
    parsed$kaynak_url   <- url
    parsed$cekim_tarihi <- Sys.Date()
    all_results[[as.character(donem)]] <- parsed
  } else {
    log_msg(sprintf("  UYARI: Donem %d icin hicbir kayit elde edilemedi!", donem))
  }
}

# ── Birleştir ve kaydet ───────────────────────────────────────────────────────
mv_all <- bind_rows(all_results) |>
  select(donem, sicil, isim_ham, il, parti, kaynak_url, cekim_tarihi) |>
  mutate(donem = as.integer(donem), sicil = as.integer(sicil))

log_msg(sprintf("Toplam birlestirilmis kayit: %d", nrow(mv_all)))

write_csv(mv_all, here("data", "processed", "mv_listesi.csv"))
write_parquet(mv_all, here("data", "processed", "mv_metadata.parquet"))
log_msg("Cikti dosyalari yazildi.")

# ── Sicil tutarlılığı kontrolü ─────────────────────────────────────────────────
cat("\n=== SICIL TUTARLILIK KONTROLU ===\n")

sicil_multi <- mv_all |>
  filter(!is.na(sicil)) |>
  group_by(sicil) |>
  summarise(n_donem    = n_distinct(donem),
            isimler    = paste(sort(unique(isim_ham)), collapse = " / "),
            donemler_v = paste(sort(unique(donem)), collapse = ","),
            .groups    = "drop") |>
  filter(n_donem > 1)

cat(sprintf("Birden fazla donemde gecen sicil sayisi: %d\n", nrow(sicil_multi)))
if (nrow(sicil_multi) > 0) {
  cat("Ornekler (ilk 10):\n")
  print(head(sicil_multi, 10))
} else {
  cat("  -> Her donemde siciller benzersiz (ayni kisi farkli donemde farkli sicil alıyor)\n")
}

isim_il_multi <- mv_all |>
  filter(!is.na(sicil), !is.na(il)) |>
  group_by(isim_ham, il) |>
  summarise(n_sicil = n_distinct(sicil),
            siciller = paste(sort(unique(sicil)), collapse = ","),
            n_donem  = n_distinct(donem),
            .groups  = "drop") |>
  filter(n_sicil > 1) |>
  arrange(desc(n_sicil))

cat(sprintf("\n(isim, il) cifti icin birden fazla sicil: %d\n", nrow(isim_il_multi)))
if (nrow(isim_il_multi) > 0) {
  print(head(isim_il_multi, 10))
} else {
  cat("  -> Her (isim, il) ciftine tek sicil eslesiyor\n")
}

# ── Sanity check: 5 örnek mv ──────────────────────────────────────────────────
cat("\n=== SANITY CHECK — 5 ORNEK MV ===\n")

check_mv <- function(pattern, label) {
  hits <- mv_all |>
    filter(str_detect(str_to_upper(isim_ham), str_to_upper(pattern))) |>
    select(donem, isim_ham, il, parti, sicil) |>
    arrange(donem)
  cat(sprintf("\n[%s] — %d donem kaydı:\n", label, nrow(hits)))
  if (nrow(hits) > 0) print(as.data.frame(hits)) else cat("  Bulunamadi!\n")
}

check_mv("PAYLAN",       "Garo Paylan")
check_mv("MEH.*ŞİMŞEK|MEHMET SIMSEK", "Mehmet Şimşek")
check_mv("AKŞENER|AKSENER", "Meral Akşener")
check_mv("KILIÇDAROĞLU|KILICDAROGLU", "Kemal Kılıçdaroğlu")
check_mv("BAHÇELİ|BAHCELI", "Devlet Bahçeli")

# ── Dönem özeti ───────────────────────────────────────────────────────────────
cat("\n=== DONEM OZETI ===\n")
mv_all |>
  group_by(donem) |>
  summarise(
    n_mv    = n(),
    n_il_na = sum(is.na(il)),
    n_parti_na = sum(is.na(parti)),
    partiler = paste(sort(unique(na.omit(parti))), collapse = " | "),
    .groups = "drop"
  ) |>
  print()

log_msg("=== Tamamlandi ===")
cat(sprintf("\nLog: %s\n", log_path))
