suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(readr)
  library(stringr)
  library(here)
})

cat("=== 04h: Hacim Doğrulama + En Uzun Konuşma Kalite Kontrolü ===\n")
cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# ---- 1. Parquet yükle ----
km <- read_parquet(here("data/processed/konusmalar_metadata.parquet"))
cat("Konusmalar:", nrow(km), "\n")

# Dosya başına toplam parquet karakter sayısı
parquet_karakter <- km |>
  mutate(metin_nchar = nchar(coalesce(metin, ""))) |>
  group_by(dosya_kaynak) |>
  summarise(
    parquet_karakter = sum(metin_nchar),
    n_konusma        = n(),
    .groups = "drop"
  )

cat("Distinct dosya:", nrow(parquet_karakter), "\n\n")

# ---- 2. TXT dosyası yolunu bul ----
resolve_txt_path <- function(dk) {
  if (str_detect(dk, "_owa\\.txt$")) {
    here("data/raw/txt/owa", dk)
  } else {
    fname <- str_replace(dk, "\\.pdf$", ".txt")
    here("data/raw/txt/sbb", fname)
  }
}

parquet_karakter <- parquet_karakter |>
  mutate(txt_path = sapply(dosya_kaynak, resolve_txt_path))

# ---- 3. Ham TXT nchar ----
cat("Ham TXT dosyaları okunuyor (", nrow(parquet_karakter), "dosya)...\n")

ham_karakter_vec <- vapply(parquet_karakter$txt_path, function(p) {
  if (!file.exists(p)) return(NA_real_)
  txt <- tryCatch(
    read_file(p),
    error = function(e) NA_character_
  )
  if (is.na(txt)) NA_real_ else as.numeric(nchar(txt))
}, numeric(1))

parquet_karakter <- parquet_karakter |>
  mutate(
    ham_karakter = ham_karakter_vec,
    dosya_var    = !is.na(ham_karakter),
    parse_oran   = ifelse(dosya_var & ham_karakter > 0,
                          parquet_karakter / ham_karakter, NA_real_)
  )

cat("Bulunamayan TXT:", sum(!parquet_karakter$dosya_var), "\n\n")

# ---- 4. Özet istatistik ----
mevcut <- parquet_karakter |> filter(dosya_var)

cat("=== HACIM DOĞRULAMA ÖZET ===\n")
cat(sprintf("Dosya sayısı       : %d\n", nrow(mevcut)))
cat(sprintf("Medyan parse oranı : %%%.1f\n", median(mevcut$parse_oran, na.rm = TRUE) * 100))
cat(sprintf("Min parse oranı    : %%%.1f\n", min(mevcut$parse_oran, na.rm = TRUE) * 100))
cat(sprintf("Max parse oranı    : %%%.1f\n", max(mevcut$parse_oran, na.rm = TRUE) * 100))
cat(sprintf("%%5 quantile        : %%%.1f\n",
            quantile(mevcut$parse_oran, 0.05, na.rm = TRUE) * 100))
cat(sprintf("%%25 quantile       : %%%.1f\n",
            quantile(mevcut$parse_oran, 0.25, na.rm = TRUE) * 100))

# Uyarı bayrağı: parse_oran < 0.5
dusuk <- mevcut |> filter(parse_oran < 0.5) |> arrange(parse_oran)
cat(sprintf("\nUyarı (oran < %%50): %d dosya\n", nrow(dusuk)))

if (nrow(dusuk) > 0) {
  cat("\n--- Aykırı dosyalar (en düşük 5) ---\n")
  print(dusuk |>
    select(dosya_kaynak, n_konusma, ham_karakter, parquet_karakter, parse_oran) |>
    head(5))
}

# ---- 5. CSV kaydet ----
write_csv(
  parquet_karakter |>
    select(dosya_kaynak, n_konusma, ham_karakter, parquet_karakter, parse_oran, dosya_var) |>
    arrange(parse_oran),
  here("data/processed/hacim_dogrulama.csv")
)
cat("\nhacim_dogrulama.csv yazıldı.\n")

# ---- 6. Aykırı dosyaları incele ----
if (nrow(dusuk) > 0) {
  cat("\n=== AYKIRI DOSYA İÇERİK ÖNİZLEME (ilk 5) ===\n")
  for (i in seq_len(min(5, nrow(dusuk)))) {
    p   <- dusuk$txt_path[i]
    cat(sprintf("\n[%d] %s (oran: %%%.1f)\n",
                i, dusuk$dosya_kaynak[i], dusuk$parse_oran[i] * 100))
    txt <- tryCatch(read_file(p), error = function(e) "OKUNAMADI")
    cat("  İlk 300 karakter:\n  ",
        str_trunc(str_squish(substr(txt, 1, 500)), 300), "\n")
  }
}

cat("\n", strrep("=", 55), "\n", sep = "")
cat("ADIM 1 TAMAMLANDI.\n\n")

# ===========================================================
# ADIM 2 — En uzun 10 konuşma kalite kontrolü
# ===========================================================
cat("=== ADIM 2: EN UZUN 10 KONUŞMA KALİTE KONTROLÜ ===\n\n")

uzun10 <- km |>
  filter(!is.na(kelime_sayisi) & !is.na(metin)) |>
  slice_max(kelime_sayisi, n = 10, with_ties = FALSE) |>
  select(konusma_id, tarih, konusmaci_ham, kelime_sayisi, metin)

for (i in seq_len(nrow(uzun10))) {
  row  <- uzun10[i, ]
  metin <- row$metin
  n    <- nchar(metin)

  cat(sprintf("--- [%d] %s ---\n", i, row$konusma_id))
  cat(sprintf("    Tarih : %s\n", row$tarih))
  cat(sprintf("    Kim   : %s\n", row$konusmaci_ham))
  cat(sprintf("    Kelime: %d\n", row$kelime_sayisi))
  cat("    İlk 200 karakter:\n    ")
  cat(str_trunc(substr(metin, 1, 200), 200))
  cat("\n    Son 200 karakter:\n    ")
  cat(str_trunc(substr(metin, max(1L, n - 200L), n), 200))
  cat("\n\n")
}

cat("ADIM 2 TAMAMLANDI.\n")
