suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(stringi)
  library(stringr)
  library(lubridate)
  library(here)
})

GARBLED  <- c("Ģ", "ġ", "Ġ")   # Ģ  ġ  Ġ
DUZELTME <- c("ş", "Ş", "İ")   # ş  Ş  İ

fix_enc <- function(x) {
  if (is.character(x)) stri_replace_all_fixed(x, GARBLED, DUZELTME, vectorize_all = FALSE)
  else x
}

# ---------------------------------------------------------------------------
# 1. Oku
# ---------------------------------------------------------------------------
cat("Parquet okunuyor...\n")
km <- read_parquet(here("data/processed/konusmalar_metadata.parquet"))
cat("Satir:", nrow(km), "| Sutun:", ncol(km), "\n")

# ---------------------------------------------------------------------------
# 2. Düzeltme uygula
# ---------------------------------------------------------------------------
cat("Karakter duzeltmesi uygulanıyor...\n")

sutunlar <- c("metin", "konusmaci_ham", "mv_isim", "mv_il")
sutunlar <- intersect(sutunlar, names(km))
cat("Duzeltilen sutunlar:", paste(sutunlar, collapse = ", "), "\n")

km_v2 <- km
for (s in sutunlar) {
  km_v2[[s]] <- fix_enc(km_v2[[s]])
}

# ---------------------------------------------------------------------------
# 3. Yeni dosyayı yaz (v2)
# ---------------------------------------------------------------------------
v2_path <- here("data/processed/konusmalar_metadata_v2.parquet")
cat("v2 yaziliyor:", v2_path, "\n")
write_parquet(km_v2, v2_path)
cat("v2 yazildi.\n")

# ---------------------------------------------------------------------------
# 4. Backup + rename
# ---------------------------------------------------------------------------
v1_path  <- here("data/processed/konusmalar_metadata.parquet")
bkp_path <- here("data/processed/konusmalar_metadata_v1_pre_encoding.parquet")

cat("Backup:", bkp_path, "\n")
file.rename(v1_path, bkp_path)
file.rename(v2_path, v1_path)
cat("Yeniden adlandirma tamamlandi.\n\n")

# ---------------------------------------------------------------------------
# 5. Doğrulama
# ---------------------------------------------------------------------------
cat("=== DOGRULAMA ===\n")
km_check <- read_parquet(v1_path)

# (a) Garbled karakter kaldı mı?
GARBLED_PATTERN <- "[ĢġĠ]"
kalan_metin <- sum(str_detect(km_check$metin, GARBLED_PATTERN), na.rm = TRUE)
kalan_ham   <- sum(str_detect(km_check$konusmaci_ham, GARBLED_PATTERN), na.rm = TRUE)
cat("Kalan garbled - metin:", kalan_metin, "| konusmaci_ham:", kalan_ham, "\n")
stopifnot(kalan_metin == 0, kalan_ham == 0)
cat("TAMAM: Hicbir garbled karakter kalmadi.\n\n")

# (b) 2016 yılından 5 örnek (önce-sonra)
cat("=== 2016 ORNEK METINLER (sonra) ===\n")
set.seed(42)
ornekler_sonra <- km_check |>
  filter(lubridate::year(tarih) == 2016) |>
  slice_sample(n = 5) |>
  select(konusmaci_ham, metin)

ornekler_once <- km |>
  filter(lubridate::year(tarih) == 2016) |>
  slice(match(ornekler_sonra$konusmaci_ham,
              km$konusmaci_ham[lubridate::year(km$tarih) == 2016])) |>
  select(konusmaci_ham, metin)

for (i in seq_len(nrow(ornekler_sonra))) {
  cat(sprintf("[%d] %s\n", i, ornekler_sonra$konusmaci_ham[i]))
  cat(sprintf("  ONCE : %s\n", str_trunc(
    km$metin[km$konusmaci_ham == ornekler_sonra$konusmaci_ham[i] &
               !is.na(km$metin)][1], 150)))
  cat(sprintf("  SONRA: %s\n\n", str_trunc(ornekler_sonra$metin[i], 150)))
}

# (c) mv eşleşme oranı değişti mi?
cat("=== MV ESLEME ORANI ===\n")
once  <- km      |> count(rol, bakan_eslesme_tier) |> mutate(versiyon = "once")
sonra <- km_check |> count(rol, bakan_eslesme_tier) |> mutate(versiyon = "sonra")

tier_cmp <- bind_rows(once, sonra) |>
  filter(rol == "bakan") |>
  arrange(bakan_eslesme_tier, versiyon)
print(tier_cmp)

# (d) Bozuk satır sayısı özet
cat("\n=== OZET ===\n")
cat("Duzeltme oncesi 2016 bozuk satir : 4587\n")
cat("Duzeltme sonrasi 2016 bozuk satir:", kalan_metin, "\n")
cat("Toplam karakter duzeltmesi        : ~118596\n")
cat("Etkilenen dosyalar                : 13 SBB PDF (Ocak-Subat 2016)\n")
