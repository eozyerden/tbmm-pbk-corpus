# R/parse_helpers.R
# Aşama 2: tutanak metinlerini konuşma satırlarına ayırma yardımcı fonksiyonları

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
})

# ---- Türkçe harf dönüşümleri ----
tr_tolower <- function(x) {
  chartr(
    "ABCÇDEFGĞHIİJKLMNOÖPRSŞTUÜVYZ",
    "abcçdefgğhıijklmnoöprsştuüvyz",
    x
  )
}

tr_toupper <- function(x) {
  chartr(
    "abcçdefgğhıijklmnoöprsştuüvyz",
    "ABCÇDEFGĞHIİJKLMNOÖPRSŞTUÜVYZ",
    x
  )
}

tr_totitle <- function(x) {
  words <- strsplit(x, "\\s+")[[1L]]
  words <- vapply(words, function(w) {
    if (nchar(w) == 0L) return(w)
    paste0(tr_toupper(substr(w, 1L, 1L)),
           tr_tolower(substr(w, 2L, nchar(w))))
  }, character(1L))
  paste(words, collapse = " ")
}

# ---- PDF satırlarını temizle ----
# Girdi : character vector (readLines çıktısı)
# Çıktı : temizlenmiş character vector (sayfa başlıkları, ToC, gürültü kaldırılmış)
clean_pdf_text <- function(lines) {
  if (length(lines) == 0L) return(lines)

  # 1. OWA ToC bloğu: "S Ö Z AL AN L AR" → ilk divider veya oturum başlığı
  toc_start <- grep("S\\s*[ÖO]\\s*Z\\s*AL\\s*AN\\s*L\\s*AR", lines, perl = TRUE)[1L]
  if (!is.na(toc_start)) {
    suffix   <- seq_len(length(lines) - toc_start) + toc_start
    div_pat  <- "^\\s*[-_]{3,}\\s*[O0]\\s*[-_]{3,}\\s*$"
    otur_pat <- "^\\s*(BİRİNCİ|İKİNCİ|ÜÇÜNCÜ|DÖRDÜNCÜ|BEŞİNCİ)\\s+OTURUM"
    ends     <- c(grep(div_pat,  lines[suffix], perl = TRUE),
                  grep(otur_pat, lines[suffix], perl = TRUE))
    toc_end  <- if (length(ends) > 0L) suffix[min(ends)] - 1L else toc_start
    lines    <- lines[-seq(toc_start, toc_end)]
  }

  # 2. OWA sayfa başlığı (3 satır): "^\s*TBMM\s*$" + "Tutanak Müdürlüğü" + "Sayfa :"
  keep <- rep(TRUE, length(lines))
  for (i in seq_len(length(lines) - 2L)) {
    if (grepl("^\\s*TBMM\\s*$",        lines[i],      perl = TRUE) &&
        grepl("Tutanak\\s*Müdürlüğü",   lines[i + 1L], perl = TRUE) &&
        grepl("Sayfa\\s*:",             lines[i + 2L], perl = TRUE)) {
      keep[c(i, i + 1L, i + 2L)] <- FALSE
    }
  }
  lines <- lines[keep]

  # 3. SBB çapraz sayfa gürültüsü: "TBMM   B: N   DD . M . YYYY"
  lines <- lines[!grepl(
    "^\\s*TBMM\\s+B:\\s*\\d+\\s+\\d+\\s*\\.\\s*\\d+\\s*\\.\\s*\\d{4}",
    lines, perl = TRUE)]

  # 4. SBB sayfa alt başlığı: "Plan ve Bütçe Komisyonu" tek satır
  lines <- lines[!grepl("^\\s*Plan ve Bütçe Komisyonu\\s*$", lines, perl = TRUE)]

  # 5. SBB T:/O: satırı: "DD . MM . YYYY   T: N   O: N"
  lines <- lines[!grepl(
    "^\\s*\\d{1,2}\\s*\\.\\s*\\d{1,2}\\s*\\.\\s*\\d{4}\\s+T:\\s*\\d+\\s+O:\\s*\\d+",
    lines, perl = TRUE)]

  # 6. Yalnız sayfa numarası (sadece boşluk + rakam)
  lines <- lines[!grepl("^\\s*\\d{1,4}\\s*$", lines, perl = TRUE)]

  # 7. ToC nokta girdileri (AD .....  N) — artakalanlar
  lines <- lines[!grepl("\\.{5,}\\s*\\d+\\s*$", lines, perl = TRUE)]

  # 8. Divider satırları
  lines <- lines[!grepl("^\\s*[-_]{3,}\\s*[O0]\\s*[-_]{3,}\\s*$", lines, perl = TRUE)]

  lines
}

# ---- Konuşmacı satırı regex ----
# Biçim: {2+boşluk}{AD/UNVAN}[( Şehir)] {tire} {metin başlangıcı}
# Tire: U+002D (-), U+2013 (–), U+2014 (—)
# Karakter sınıfı: TR büyük harfler (Î/Â dahil) + boşluk + nokta (PROF. DR. için)
.SPEAKER_RE <- paste0(
  "^\\s{2,}",
  "([A-ZÇĞİÖŞÜÂÎÛ][A-ZÇĞİÖŞÜÂÎÛ .]+?)",
  "(?:\\s*\\(([^)]+)\\))?",
  "\\s*[-–—]\\s+",
  "(.*)"
)

# Minimum 4 karakter + Roma rakam section başlıklarını eler (I., II., I I., I I I. ...)
is_speaker_line <- function(line) {
  m <- regmatches(line, regexec(.SPEAKER_RE, line, perl = TRUE))[[1L]]
  if (length(m) == 0L) return(FALSE)
  ham <- trimws(m[2L])
  nchar(ham) >= 4L && !grepl("^[IVXLCDM][IVXLCDM\\s]*\\.\\s*$", ham, perl = TRUE)
}

# ---- Konuşmacı satırını ayrıştır ----
# Döndürür: list(konusmaci_ham, sehir, metin_baslangic) veya NULL
parse_speaker_line <- function(line) {
  m <- regmatches(line, regexec(.SPEAKER_RE, line, perl = TRUE))[[1L]]
  if (length(m) == 0L) return(NULL)
  list(
    konusmaci_ham   = trimws(m[2L]),
    sehir           = if (nchar(trimws(m[3L])) == 0L) NA_character_ else trimws(m[3L]),
    metin_baslangic = trimws(m[4L])
  )
}

# ---- Rol sınıflandır ----
# Hiyerarşi (öncelik sırasıyla): burokrat > baskan > bakan > milletvekili
# Burokrat önce: SAYIŞTAY/MERKEZ BANKASI gibi "BAŞKANI" içeren unvanlar yanlış
# sınıflandırılmasın.
classify_role <- function(konusmaci_ham) {
  x <- tr_toupper(trimws(konusmaci_ham))

  if (grepl(paste(
    "SAYIŞTAY BAŞKANI", "MERKEZ BANKASI",  "YÖK BAŞKANI",
    "KURUL BAŞKANI",    "BAŞKANLIĞI BAŞKANI",
    "GENEL SEKRETERİ",  "GENEL MÜDÜR\\b",
    "MÜSTEŞAR\\b",      "ENSTİTÜ",        "CUMHURBAŞKANLIĞI",
    sep = "|"), x, perl = TRUE))
    return("burokrat")

  if (grepl(paste(
    "^BAŞKAN\\b", "^KOMİSYON BAŞKANI", "^OTURUM BAŞKANI",
    "^BAŞKAN VEKİLİ", "TBMM BAŞKAN VEKİLİ", "^TBMM BAŞKANI",
    "^PLAN VE BÜTÇE KOMİSYONU BAŞKANI",
    sep = "|"), x, perl = TRUE))
    return("baskan")

  if (grepl(
    "BAKANI\\b|\\bBAŞBAKAN\\b|BAŞBAKAN YARDIMCISI|CUMHURBAŞKANI YARDIMCISI",
    x, perl = TRUE))
    return("bakan")

  "milletvekili"
}

# ---- Parti çıkar ----
# "AK PARTİ GRUBU ADINA FAİK ÖZTRAK" → "AK PARTİ"
# SBB/OWA dosyalarında mevcut değil; Genel Kurul (Kaynak C) için rezerve.
extract_party <- function(konusmaci_ham) {
  m <- regmatches(
    konusmaci_ham,
    regexpr("^(.+?)\\s+GRUBU\\s+ADINA", konusmaci_ham, perl = TRUE)
  )
  if (length(m) == 0L || nchar(m) == 0L) return(NA_character_)
  trimws(sub("\\s+GRUBU\\s+ADINA.*", "", m, perl = TRUE))
}

# ---- İsim normalleştir ----
# "MALİYE BAKANI MEHMET ŞİMŞEK" → "Mehmet Şimşek"
# "MUSA ÇAM"                     → "Musa Çam"
# "BAŞKAN"                        → "Başkan"
normalize_name <- function(konusmaci_ham) {
  x <- trimws(konusmaci_ham)
  if (is.na(x) || nchar(x) == 0L) return(NA_character_)

  words <- strsplit(x, "\\s+")[[1L]]
  if (length(words) <= 2L) return(tr_totitle(x))

  # Son unvan eki olan kelimeyi bul; sonrasındaki kelimeler kişi adıdır
  role_sfx <- c("BAKANI", "YARDIMCISI", "VEKİLİ", "BAŞKANI", "SEKRETERİ",
                "MÜSTEŞARI", "MÜDÜRÜ", "SÖZCÜSÜ", "SAVCISI", "REKTÖRÜ",
                "KOMUTANI")

  last_role <- 0L
  for (i in seq_along(words)) {
    if (tr_toupper(words[i]) %in% role_sfx) last_role <- i
  }

  name_words <- if (last_role > 0L && last_role < length(words))
    words[(last_role + 1L):length(words)]
  else
    words

  tr_totitle(paste(name_words, collapse = " "))
}

# ---- Tutanağı konuşmalara böl ----
# Girdi : clean_pdf_text() çıktısı + dosya metadata'sı
# Çıktı : tibble, her satır = bir konuşmacı turu
split_into_speeches <- function(lines,
                                dosya_kaynak = NA_character_,
                                kaynak       = NA_character_,
                                tarih        = as.Date(NA),
                                butce_yili   = NA_integer_) {
  if (length(lines) == 0L) return(tibble())

  speaker_idx <- which(vapply(lines, is_speaker_line, logical(1L),
                              USE.NAMES = FALSE))
  if (length(speaker_idx) == 0L) return(tibble())

  speeches <- vector("list", length(speaker_idx))

  for (i in seq_along(speaker_idx)) {
    si  <- speaker_idx[i]
    end <- if (i < length(speaker_idx)) speaker_idx[i + 1L] - 1L else length(lines)

    parsed <- parse_speaker_line(lines[si])
    if (is.null(parsed)) next

    cont_range <- if (si + 1L <= end) seq(si + 1L, end) else integer(0L)
    cont       <- lines[cont_range]
    cont       <- cont[nchar(trimws(cont)) > 0L]
    metin      <- paste(c(parsed$metin_baslangic, cont), collapse = " ")
    metin      <- trimws(gsub("\\s{2,}", " ", metin))

    kham <- parsed$konusmaci_ham
    rol  <- classify_role(kham)
    kel  <- length(strsplit(metin, "\\s+")[[1L]])

    speeches[[i]] <- tibble(
      dosya_kaynak   = dosya_kaynak,
      kaynak         = kaynak,
      tarih          = tarih,
      butce_yili     = as.integer(butce_yili),
      oturum_sira    = i,
      konusmaci_ham  = kham,
      konusmaci_sade = normalize_name(kham),
      sehir          = parsed$sehir,
      rol            = rol,
      parti_metinde  = extract_party(kham),
      metin          = metin,
      kelime_sayisi  = as.integer(kel),
      is_baskanlik   = rol == "baskan",
      is_kisa        = kel < 20L
    )
  }

  result <- bind_rows(Filter(Negate(is.null), speeches))

  if (nrow(result) > 0L) {
    result <- result |>
      mutate(
        konusma_id = sprintf("%s_%s_%03d",
                             kaynak,
                             format(as.Date(tarih), "%Y%m%d"),
                             oturum_sira)
      ) |>
      select(konusma_id, everything())
  }

  result
}

# ---- Birim testleri ----
# Çalıştır: source("R/parse_helpers.R"); test_parse_helpers()
test_parse_helpers <- function() {
  cases <- list(
    # speaker=T, rol testi — orijinal 8 vaka
    list(line = "  MALİYE BAKANI MEHMET ŞİMŞEK - Teşekkür ederim.",
         exp_speaker = TRUE,  exp_rol = "bakan"),
    list(line = "  MUSA ÇAM (İzmir) - Sayın Başkan değerli",
         exp_speaker = TRUE,  exp_rol = "milletvekili"),
    list(line = "  BAŞKAN - Söz veriyorum.",
         exp_speaker = TRUE,  exp_rol = "baskan"),
    list(line = "  PROF. DR. MEHMET YILMAZ - Sunumuma geçiyorum.",
         exp_speaker = TRUE,  exp_rol = "milletvekili"),
    list(line = "  MİLLÎ EĞİTİM BAKANI ZİYA SELÇUK - Teşekkür ederim.",
         exp_speaker = TRUE,  exp_rol = "bakan"),
    list(line = "  SAYIŞTAY BAŞKANI MEHMET BARIŞ ÖZCAN - Değerli üyeler",
         exp_speaker = TRUE,  exp_rol = "burokrat"),
    list(line = "  MERKEZ BANKASI BAŞKANI HAFİZE ERKAN - Sunumuma",
         exp_speaker = TRUE,  exp_rol = "burokrat"),
    list(line = "Normal metin satırı herhangi bir içerik.",
         exp_speaker = FALSE, exp_rol = NULL),
    # yeni başkan vakaları
    list(line = "  BAŞKAN MEHMET MUŞ - Teşekkür ederim.",
         exp_speaker = TRUE,  exp_rol = "baskan"),
    list(line = "  BAŞKAN CEVDET YILMAZ - Buyurunuz.",
         exp_speaker = TRUE,  exp_rol = "baskan"),
    list(line = "  OTURUM BAŞKANI ALİ AŞLIK - Söz aldı.",
         exp_speaker = TRUE,  exp_rol = "baskan"),
    list(line = "  PLAN VE BÜTÇE KOMİSYONU BAŞKANI LÜTFÜ TÜRKKAN - Evet",
         exp_speaker = TRUE,  exp_rol = "baskan"),
    # yeni boşluklu Roma rakam vakaları
    list(line = "  I I . - Madde başlığı metni",
         exp_speaker = FALSE, exp_rol = NULL),
    list(line = "  I I I . - Alt başlık içeriği",
         exp_speaker = FALSE, exp_rol = NULL),
    list(line = "  I V . - Bölüm başlığı",
         exp_speaker = FALSE, exp_rol = NULL)
  )

  n_pass <- 0L
  for (i in seq_along(cases)) {
    tc  <- cases[[i]]
    spk <- is_speaker_line(tc$line)
    ok_spk <- identical(spk, tc$exp_speaker)
    ok_rol <- TRUE
    if (spk && !is.null(tc$exp_rol)) {
      parsed <- parse_speaker_line(tc$line)
      if (!is.null(parsed)) {
        rol <- classify_role(parsed$konusmaci_ham)
        ok_rol <- identical(rol, tc$exp_rol)
        if (!ok_rol)
          cat(sprintf("FAIL  #%02d rol: beklenen='%s' gerçek='%s'  (%s)\n",
                      i, tc$exp_rol, rol, trimws(tc$line)))
      }
    }
    if (!ok_spk)
      cat(sprintf("FAIL  #%02d speaker: beklenen=%s gerçek=%s  (%s)\n",
                  i, tc$exp_speaker, spk, trimws(tc$line)))
    if (ok_spk && ok_rol) n_pass <- n_pass + 1L
  }
  cat(sprintf("\nSonuç: %d/%d geçti\n", n_pass, length(cases)))
  invisible(n_pass == length(cases))
}
