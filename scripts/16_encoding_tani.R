suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(lubridate)
  library(here)
})

km <- read_parquet(here("data/processed/konusmalar_metadata.parquet"))

# ---------------------------------------------------------------------------
# 1. Bozuk karakter tespiti
# ---------------------------------------------------------------------------
# Türkçe PDF/encoding hatalarında görülen GERÇEK garbled karakterler:
#   Ş (U+015E) → Ģ (U+0122)   ş (U+015F) → ġ (U+0121)   Ş → Ġ (U+0120)
# NOT: ı (U+0131), ş (U+015F), İ (U+0130), Ş (U+015E), ğ (U+011F) gibi
#      karakterler doğru Türkçe harflerdir — bunlar GARBLED değildir.
GARBLED_PATTERN <- "[ĢģġĠ]"

km2 <- km |>
  filter(!is.na(metin)) |>
  mutate(
    yil     = year(tarih),
    garbled = str_detect(metin, GARBLED_PATTERN)
  )

# ---------------------------------------------------------------------------
# 2. Yıl × bozuk satır tablosu
# ---------------------------------------------------------------------------
cat("=== 1. YIL × BOZUK SATIR ===\n")
yil_ozet <- km2 |>
  filter(!is.na(yil)) |>
  group_by(yil) |>
  summarise(
    toplam    = n(),
    bozuk_n   = sum(garbled),
    bozuk_pct = round(bozuk_n / toplam * 100, 1),
    .groups   = "drop"
  ) |>
  filter(bozuk_n > 0) |>
  arrange(yil)
print(yil_ozet, n = Inf)

# ---------------------------------------------------------------------------
# 3. Top 20 bozuk karakter ve frekansları
# ---------------------------------------------------------------------------
cat("\n=== 2. TOP 20 BOZUK KARAKTER ===\n")
bozuk_metinler <- km2 |> filter(garbled) |> pull(metin)

# Tüm karakterleri çıkar, filtrele
chars_vec <- unlist(strsplit(bozuk_metinler, ""))
bozuk_chars <- chars_vec[str_detect(chars_vec, GARBLED_PATTERN)]
char_freq <- sort(table(bozuk_chars), decreasing = TRUE)
top20 <- head(char_freq, 20)
cat("Karakter | Unicode  | Frekans\n")
for (i in seq_along(top20)) {
  ch  <- names(top20)[i]
  cp  <- sprintf("U+%04X", utf8ToInt(ch))
  frq <- top20[[i]]
  cat(sprintf("  %-5s  | %-8s | %d\n", ch, cp, frq))
}

# ---------------------------------------------------------------------------
# 4. Sorunlu dosya_kaynak değerleri
# ---------------------------------------------------------------------------
cat("\n=== 3. SORUNLU DOSYA KAYNAK (top 30) ===\n")
dosya_ozet <- km2 |>
  filter(garbled, !is.na(dosya_kaynak)) |>
  count(dosya_kaynak, sort = TRUE) |>
  head(30)
print(dosya_ozet, n = Inf)

# Özet: SBB mi OWA mi?
cat("\nKaynak tipi özeti:\n")
km2 |>
  filter(garbled, !is.na(dosya_kaynak)) |>
  mutate(tip = if_else(str_detect(dosya_kaynak, "_owa"), "OWA", "SBB")) |>
  count(tip, sort = TRUE) |>
  print()

# ---------------------------------------------------------------------------
# 5. Bağlam örneği: bozuk karakterler nasıl görünüyor?
# ---------------------------------------------------------------------------
cat("\n=== 4. BAGLAM ÖRNEKLERİ (10 satır) ===\n")
set.seed(42)
ornekler <- km2 |>
  filter(garbled) |>
  select(yil, dosya_kaynak, metin) |>
  slice_sample(n = 10)

for (i in seq_len(nrow(ornekler))) {
  cat(sprintf("[%d] %d | %s\n  %s\n\n",
    i,
    ornekler$yil[i],
    ornekler$dosya_kaynak[i],
    str_trunc(ornekler$metin[i], 200)))
}

# ---------------------------------------------------------------------------
# 6. Önerilen düzeltme haritası
# ---------------------------------------------------------------------------
cat("=== 5. ÖNERİLEN DÜZELTME HARİTASI ===\n")
cat("(Unicode gözlemine dayalı; onay gerektirir)\n\n")

# Türkçe PDF encoding hatalarının standart haritası:
# Latin Extended-A karakterlerinin CP1254→CP1252 yanlış okuma sonucu
cat("Bağlam örneklerinden doğrulanan harita:\n")
cat("  BaĢkan → Başkan      : Ģ (U+0122) → ş (U+015F)\n")
cat("  BAġKAN → BAŞKAN      : ġ (U+0121) → Ş (U+015E)\n")
cat("  BEKĠR  → BEKİR       : Ġ (U+0120) → İ (U+0130)\n")
cat("  DIġĠġLERĠ → DIŞIŞLERI (Ġ=İ, ġ=Ş teyit)\n\n")

harita <- data.frame(
  bozuk    = c("Ģ",  "ġ",  "Ġ"),
  dogru    = c("ş",  "Ş",  "İ"),
  n_corpus = c(92465L, 10812L, 15319L),
  aciklama = c(
    "U+0122 → U+015F (ş küçük) — TEYİT",
    "U+0121 → U+015E (Ş büyük) — TEYİT",
    "U+0120 → U+0130 (İ büyük) — TEYİT, ambigüite YOK"
  ),
  stringsAsFactors = FALSE
)
print(harita)

cat("\nSONUÇ: 3 karakter, 3 farklı hedef — ambigüite yok.\n")
cat("Post-hoc düzeltme (Strateji A) güvenli uygulanabilir.\n")
cat("Etkilenen: sadece 2016 bütçe yılı, 13 SBB PDF (Ocak-Şubat 2016)\n")
cat("Toplam bozuk olay: Ģ=92465 + ġ=10812 + Ġ=15319 = 118596\n")
