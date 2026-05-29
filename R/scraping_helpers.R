# R/scraping_helpers.R
# Scraping pipeline için yardimci fonksiyonlar

log_msg <- function(msg, level = "INFO") {
  cat(sprintf("[%s] [%s] %s\n",
              format(Sys.time(), "%Y-%m-%d %H:%M:%S"), level, msg))
}

# "30 Ekim 2024" veya "30-Kasım-2017" -> "2024-10-30" (karakter)
parse_tr_date <- function(text) {
  aylar <- c(
    "ocak" = 1L, "şubat" = 2L, "mart" = 3L, "nisan" = 4L,
    "mayıs" = 5L, "haziran" = 6L, "temmuz" = 7L, "ağustos" = 8L,
    "eylül" = 9L, "ekim" = 10L, "kasım" = 11L, "aralık" = 12L
  )
  text_lower <- tolower(trimws(text))
  # \p{L}+ : Unicode harf sinifi -- Turkce karakterleri de yakalar
  m <- regmatches(
    text_lower,
    regexpr("(\\d{1,2})[\\s\\-]+([\\p{L}]+)[\\s\\-]+(\\d{4})",
            text_lower, perl = TRUE)
  )
  if (length(m) == 0 || nchar(m) == 0) return(NA_character_)
  parts <- strsplit(m, "[\\s\\-]+", perl = TRUE)[[1]]
  if (length(parts) < 3) return(NA_character_)
  gun  <- suppressWarnings(as.integer(parts[1]))
  ay_n <- aylar[[parts[2]]]
  yil  <- suppressWarnings(as.integer(parts[length(parts)]))
  if (is.null(ay_n) || is.na(ay_n) || is.na(gun) || is.na(yil)) return(NA_character_)
  tryCatch(
    as.character(as.Date(sprintf("%04d-%02d-%02d", yil, ay_n, gun))),
    error = function(e) NA_character_
  )
}

tr_to_ascii <- function(x) {
  from <- c("ç", "ğ", "ı", "ö", "ş", "ü",
            "Ç", "Ğ", "İ", "Ö", "Ş", "Ü")
  to   <- c("c", "g", "i", "o", "s", "u", "C", "G", "I", "O", "S", "U")
  for (i in seq_along(from)) x <- gsub(from[i], to[i], x, fixed = TRUE)
  x
}

# 0-10 kalite skoru: anahtar kelime varligi + harf orani
text_quality_score <- function(text) {
  if (is.null(text) || length(text) == 0) return(0)
  combined <- paste(text, collapse = " ")
  if (nchar(combined) < 100) return(0)
  keywords <- c("başkan", "bakan", "bütçe",
                "milletvekili", "komisyon", "teşekkür")
  kw_hits   <- sum(sapply(keywords, function(k)
    grepl(k, combined, ignore.case = TRUE)))
  kw_score  <- min(kw_hits / length(keywords) * 7, 7)
  n_chars   <- nchar(combined)
  n_letters <- nchar(gsub("[^[:alpha:]]", "", combined))
  ratio_score <- min((n_letters / n_chars) * 3, 3)
  round(kw_score + ratio_score, 1)
}

write_utf8 <- function(text, path) {
  con <- file(path, open = "w", encoding = "UTF-8")
  on.exit(close(con))
  writeLines(text, con)
}

# ---- TBMM OWA fonksiyonlari ----

# Plan-Butce Komisyonu tutanak liste URL'si (Kodu=17)
owa_list_url <- function(donem, yasama_yili) {
  sprintf(
    paste0("https://www.tbmm.gov.tr/Tutanaklar/",
           "KomisyonTutanaklariDonemTutanaklari",
           "?Kodu=17&DonemKodu=%d&YasamaYili=%d"),
    as.integer(donem), as.integer(yasama_yili)
  )
}

# Tutanak PDF URL'si
owa_pdf_url <- function(id) {
  sprintf("https://www.tbmm.gov.tr/Tutanaklar/TutanakGoster/%d",
          as.integer(id))
}

# Liste HTML'inden tutanak ID + baslik + tarih satirlarini cikar.
# Gercek HTML yapisi: <tr> icinde iki <td>:
#   TD[1]: <a href="/Tutanaklar/TutanakGoster/{ID}">DD/MM/YYYYTARİHLİ TOPLANTI</a>
#   TD[2]: Gercek baslik metni (link degil, duz metin)
parse_owa_tutanak_list <- function(html_page) {
  nodes <- rvest::html_elements(html_page, "a[href*='TutanakGoster']")
  if (length(nodes) == 0) {
    return(tibble::tibble(
      tutanak_id = integer(),
      baslik     = character(),
      tarih_raw  = character()
    ))
  }

  href <- rvest::html_attr(nodes, "href")
  id   <- suppressWarnings(
    as.integer(sub(".*/TutanakGoster/(\\d+).*", "\\1", href))
  )

  # Tarih: link metninden "DD/MM/YYYY" cek
  link_text <- rvest::html_text(nodes, trim = TRUE)
  tarih_raw <- vapply(link_text, function(lt) {
    m <- regmatches(lt, regexpr("\\d{2}/\\d{2}/\\d{4}", lt))
    if (length(m) == 0 || nchar(m) == 0) NA_character_ else m[[1]]
  }, character(1L), USE.NAMES = FALSE)

  # Baslik: ayni <tr> icindeki TD[2] metni
  baslik <- vapply(nodes, function(node) {
    tds <- tryCatch(
      rvest::html_elements(xml2::xml_parent(xml2::xml_parent(node)), "td"),
      error = function(e) NULL
    )
    if (is.null(tds) || length(tds) < 2) return(NA_character_)
    trimws(rvest::html_text(tds[[2]], trim = TRUE))
  }, character(1L))

  tibble::tibble(tutanak_id = id, baslik = baslik, tarih_raw = tarih_raw) |>
    dplyr::filter(!is.na(tutanak_id))
}

# "DD/MM/YYYY" -> Date
parse_dmy <- function(x) {
  as.Date(x, format = "%d/%m/%Y")
}

# Butce gorusmesi mi? (baslik tabanli filtre)
# BÜTÇE = BÜTÇE, KESİNHESAP = KESİNHESAP
is_butce_tutanak <- function(baslik) {
  pat <- paste(
    "BÜTÇE KANUNU TASARISI",
    "BÜTÇE VE KESİNHESAP",
    "BÜTÇE TASARILARI",
    "BAKANININ.*BÜTÇE",
    "BÜTÇE.*SUNUM",
    sep = "|"
  )
  grepl(pat, toupper(baslik), perl = TRUE)
}
