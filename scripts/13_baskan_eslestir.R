# Başkan rolündeki konuşmaları mv_metadata ile eşleştirir.
# Girdi : data/processed/konusmalar_metadata.parquet
#         data/processed/mv_metadata.parquet
# Çıktı : data/processed/konusmalar_metadata.parquet (baskan satırlarında mv_sicil dolu)
#         data/processed/baskan_eslestirme.csv (özet)
#
# Başkan türleri:
#   A) "BAŞKAN X"             → PBK komisyon başkanı (isim içeren)
#   B) "BAŞKAN"               → PBK komisyon başkanı (anonim) → butce_yili lookup
#   C) "OTURUM BAŞKANI X"     → Genel Kurul oturum başkanı
#   D) "TBMM BAŞKANI X"       → TBMM Başkanı
#   E) "TBMM BAŞKAN VEKİLİ X" → TBMM Başkan Vekili
#   F) "KOMİSYON BAŞKANI"     → anonim, B gibi işle
#   G) "BAŞKAN VEKİLİ"        → anonim komisyon yedek başkanı, B gibi işle

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(stringr)
  library(here)
  library(fs)
  library(readr)
  library(tibble)
})

source(here("R", "donem_haritasi.R"))
source(here("R", "pbk_baskan_yil.R"))   # PBK başkanı: butce_yili → kanonik isim

# ── Normalizasyon ─────────────────────────────────────────────────────────────
turkish_upper <- function(x) {
  x |> str_replace_all("i", "İ") |> str_replace_all("ı", "I") |> str_to_upper()
}

# ── Kanonik isim çıkarma: konusmaci_ham → kişi adı ───────────────────────────
# Önce başlık prefix'ini sil, ardından typo haritasını uygula.
extract_baskan_isim <- function(ham) {
  # Prefix'leri temizle
  isim <- ham |>
    str_remove("^BAŞKAN\\s+") |>
    str_remove("^OTURUM BAŞKANI\\s+") |>
    str_remove("^TBMM BAŞKANI VEKİLİ\\s+") |>
    str_remove("^TBMM BAŞKANI\\s+") |>
    str_remove("^TBMM BAŞKAN VEKİLİ\\s+") |>
    str_remove("^KOMİSYON BAŞKANI\\s+") |>
    str_trim()

  # Anonim olanlar → NA (B/F/G türü)
  if_else(isim %in% c("BAŞKAN", "BAŞKAN VEKİLİ", "KOMİSYON BAŞKANI",
                       "OTURUM BAŞKANI", "TBMM BAŞKANI", "TBMM BAŞKAN VEKİLİ"),
          NA_character_, isim)
}

# Typo haritası: ham içindeki varyantlar → kanonik kişi adı
typo_map <- tribble(
  ~ham_pattern,                                    ~kanonik_isim,
  # PBK başkanı varyantları
  "BAŞKAN CEVDET YILMAZ",                          "CEVDET YILMAZ",
  "BAŞKAN CEVDE YILMAZ",                           "CEVDET YILMAZ",
  "BAŞKAN CEVDET YILAMZ",                          "CEVDET YILMAZ",
  "BAŞKAN CEVDET YIMAZ",                           "CEVDET YILMAZ",
  "BAŞKAN LÜTFİ ELVAN",                            "LÜTFİ ELVAN",
  "BAŞKAN LÜFTİ ELVAN",                            "LÜTFİ ELVAN",
  "BAŞKAN LÜTFÜ ELVAN",                            "LÜTFİ ELVAN",
  "BAŞKAN LÜTFİ EVLAN",                            "LÜTFİ ELVAN",
  "BAŞKAN MEHMET MUŞ",                             "MEHMET MUŞ",
  "BAŞKAN MEHMUT MUŞ",                             "MEHMET MUŞ",
  "BAŞKAN MEHMET MUŞLU",                           "MEHMET MUŞ",
  "BAŞKAN ORHAN ERDEM",                            "ORHAN ERDEM",
  # Oturum başkanı varyantları
  "OTURUM BAŞKANI ABDULLAH NEJAT KOÇER",           "ABDULLAH NEJAT KOÇER",
  "OTURUM BAŞKANI ABDDULLAH NEJAT KOÇER",          "ABDULLAH NEJAT KOÇER",
  "OTURUM BAŞKANI ABDULLAH NEJAT KOJER",           "ABDULLAH NEJAT KOÇER",
  "OTURUM BAŞKANI ORHAN ERDEM",                    "ORHAN ERDEM",
  "OTURUM BAŞKANI ŞİRİN ÜNAL",                     "ŞİRİN ÜNAL",
  "OTURUM BAŞKANI İSMAİL FARUK AKSU",              "İSMAİL FARUK AKSU",
  # TBMM Başkanı varyantları
  "TBMM BAŞKANI MUSTAFA ŞENTOP",                   "MUSTAFA ŞENTOP",
  "TBMM BAŞKANI CEMİL ÇİÇEK",                     "CEMİL ÇİÇEK",
  "TBMM BAŞKANI CEMİL ÇİCEK",                     "CEMİL ÇİÇEK",
  "TBMM BAŞKANI MEHMET ALİ ŞAHİN",                "MEHMET ALİ ŞAHİN",
  "TBMM BAŞKANI NUMAN KURTULMUŞ",                  "NUMAN KURTULMUŞ",
  # TBMM Başkan Vekili varyantları
  "TBMM BAŞKANI VEKİLİ SÜREYYA SADİ BİLGİÇ",     "SÜREYYA SADİ BİLGİÇ",
  "TBMM BAŞKAN VEKİLİ SÜREYYA SADİ BİLGİÇ",      "SÜREYYA SADİ BİLGİÇ",
  "TBMM BAŞKAN VEKİLİ AHMET AYDIN",               "AHMET AYDIN",
  "TBMM BAŞKAN VEKİLİ AYŞE NUR BAHÇEKAPILI",      "AYŞE NUR BAHÇEKAPILI",
  "TBMM BAŞKAN VEKİLİ AYŞE NUR BAHÇEKAPALI",      "AYŞE NUR BAHÇEKAPILI",
  "TBMM BAŞKAN VEKİLİ NEVZAT PAKDİL",             "NEVZAT PAKDİL",
  "TBMM BAŞKAN VEKİLİ SADIK YAKUT",               "SADIK YAKUT"
) |>
  mutate(
    ham_norm    = turkish_upper(ham_pattern),
    kanonik_norm = turkish_upper(kanonik_isim)
  )

# ── Veri yükleme ─────────────────────────────────────────────────────────────
cat("Veriler yükleniyor...\n")
corpus_meta <- read_parquet(here("data","processed","konusmalar_metadata.parquet"))
mv_meta     <- read_parquet(here("data","processed","mv_metadata.parquet"))

baskan_rows <- corpus_meta |> filter(rol == "baskan")
cat(sprintf("  Başkan satırı: %d, unique konuşmacı: %d\n",
            nrow(baskan_rows),
            n_distinct(baskan_rows$konusmaci_ham)))

# ── mv_meta normalizasyon ─────────────────────────────────────────────────────
mv_norm <- mv_meta |>
  mutate(isim_norm = turkish_upper(str_trim(isim_ham))) |>
  # Bir kişinin birden fazla dönem kaydı var; sicil sabittir
  group_by(isim_norm) |>
  summarise(
    sicil     = first(sicil),
    mv_isim   = first(isim_ham),
    mv_parti  = first(parti),
    donemler  = paste(sort(unique(donem)), collapse=","),
    .groups   = "drop"
  )

# ── Başkan unique kayıtları: ham → kanonik ────────────────────────────────────
baskan_uniq <- baskan_rows |>
  distinct(konusmaci_ham, butce_yili) |>
  mutate(ham_norm = turkish_upper(str_trim(konusmaci_ham)))

# Typo haritasından kanonik isim al
baskan_uniq <- baskan_uniq |>
  left_join(typo_map |> select(ham_norm, kanonik_norm, kanonik_isim),
            by = "ham_norm")

# Typo haritasında yoksa kendin çıkar
baskan_uniq <- baskan_uniq |>
  mutate(
    kanonik_norm = if_else(
      is.na(kanonik_norm),
      turkish_upper(str_trim(extract_baskan_isim(konusmaci_ham))),
      kanonik_norm
    )
  )

# Anonim BAŞKAN → pbk_baskan_yil lookup
anonim_mask <- is.na(baskan_uniq$kanonik_norm) |
  baskan_uniq$kanonik_norm == ""

baskan_uniq <- baskan_uniq |>
  left_join(pbk_baskan_yil |> mutate(pbk_norm = turkish_upper(pbk_baskan_kanonik)),
            by = "butce_yili") |>
  mutate(
    kanonik_norm = if_else(anonim_mask,
                           pbk_norm,
                           kanonik_norm)
  ) |>
  select(-pbk_baskan_kanonik, -pbk_norm)

# ── mv_meta join ─────────────────────────────────────────────────────────────
baskan_join <- baskan_uniq |>
  left_join(mv_norm, by = c("kanonik_norm" = "isim_norm")) |>
  mutate(
    mv_sicil       = sicil,
    mv_isim        = mv_isim,
    mv_parti       = mv_parti,
    eslesme_tier   = 0L,
    eslesme_durumu = if_else(!is.na(sicil), "matched_baskan", "unmatched_baskan")
  ) |>
  select(konusmaci_ham, butce_yili,
         mv_sicil, mv_isim, mv_parti,
         eslesme_tier, eslesme_durumu,
         kanonik_norm)

# ── Corpus güncelleme ─────────────────────────────────────────────────────────
cat("\nCorpus güncelleniyor...\n")

corpus_updated <- corpus_meta |>
  left_join(
    baskan_join |> select(konusmaci_ham, butce_yili,
                          mv_sicil_b = mv_sicil,
                          mv_isim_b  = mv_isim,
                          mv_parti_b = mv_parti,
                          eslesme_tier_b   = eslesme_tier,
                          eslesme_durumu_b = eslesme_durumu),
    by = c("konusmaci_ham", "butce_yili")
  ) |>
  mutate(
    mv_sicil       = if_else(rol == "baskan" & !is.na(mv_sicil_b), mv_sicil_b,       mv_sicil),
    mv_isim        = if_else(rol == "baskan" & !is.na(mv_isim_b),  mv_isim_b,        mv_isim),
    mv_parti       = if_else(rol == "baskan" & !is.na(mv_parti_b), mv_parti_b,       mv_parti),
    eslesme_tier   = if_else(rol == "baskan", eslesme_tier_b,   eslesme_tier),
    eslesme_durumu = if_else(rol == "baskan", eslesme_durumu_b, eslesme_durumu)
  ) |>
  select(-mv_sicil_b, -mv_isim_b, -mv_parti_b,
         -eslesme_tier_b, -eslesme_durumu_b)

stopifnot(nrow(corpus_updated) == nrow(corpus_meta))

write_parquet(corpus_updated,
              here("data","processed","konusmalar_metadata.parquet"))
cat("  konusmalar_metadata.parquet güncellendi.\n")

# ── Özet CSV ─────────────────────────────────────────────────────────────────
baskan_ozet <- baskan_join |>
  group_by(konusmaci_ham, kanonik_norm, mv_sicil, mv_isim, mv_parti,
           eslesme_durumu) |>
  summarise(
    butce_yillari = paste(sort(unique(butce_yili)), collapse=","),
    konusma_n     = nrow(baskan_rows |>
                           filter(konusmaci_ham == konusmaci_ham[1])),
    .groups = "drop"
  ) |>
  arrange(desc(konusma_n))

# Konuşma sayısını düzelt (group_by içinde self-join hatası olabilir)
baskan_ozet <- baskan_join |>
  left_join(
    baskan_rows |> count(konusmaci_ham, butce_yili, name="n"),
    by = c("konusmaci_ham","butce_yili")
  ) |>
  group_by(konusmaci_ham, kanonik_norm, mv_sicil, mv_isim, mv_parti,
           eslesme_durumu) |>
  summarise(
    butce_yillari = paste(sort(unique(butce_yili)), collapse=","),
    konusma_n     = sum(n, na.rm=TRUE),
    .groups       = "drop"
  ) |>
  arrange(desc(konusma_n))

write_csv(baskan_ozet, here("data","processed","baskan_eslestirme.csv"))

# ── Konsol özeti ─────────────────────────────────────────────────────────────
matched_n   <- sum(baskan_join$eslesme_durumu == "matched_baskan",   na.rm=TRUE)
unmatched_n <- sum(baskan_join$eslesme_durumu == "unmatched_baskan", na.rm=TRUE)

cat(sprintf("\n=== BAŞKAN EŞLEŞTİRME ÖZET ===\n"))
cat(sprintf("  Matched   : %d unique (konusmaci_ham × yil)\n", matched_n))
cat(sprintf("  Unmatched : %d unique\n", unmatched_n))

cat("\n--- Kanonik isim → sicil tablosu ---\n")
baskan_ozet_uniq <- baskan_ozet |>
  distinct(kanonik_norm, mv_sicil, mv_isim, mv_parti, butce_yillari, eslesme_durumu) |>
  arrange(eslesme_durumu, kanonik_norm)
print(as.data.frame(baskan_ozet_uniq))

# PBK başkanı anonim yıllar (NA durumu)
anonim_na <- pbk_baskan_yil |> filter(is.na(pbk_baskan_kanonik))
if (nrow(anonim_na) > 0) {
  lone_baskan_na <- baskan_rows |>
    filter(konusmaci_ham %in% c("BAŞKAN","BAŞKAN VEKİLİ","KOMİSYON BAŞKANI")) |>
    filter(butce_yili %in% anonim_na$butce_yili) |>
    count(butce_yili, name="konusma_n")

  cat(sprintf("\n*** UYARI: %d yıl için PBK başkanı henüz atanmamış ***\n",
              nrow(anonim_na)))
  cat("  Etkilenen lone-BAŞKAN konuşmaları:\n")
  print(as.data.frame(lone_baskan_na))
  cat("  → pbk_baskan_yil tablosunu tamamlayıp scripti yeniden çalıştır.\n")
}
