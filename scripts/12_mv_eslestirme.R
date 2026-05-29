# Corpus konuşmacılarını (rol == "milletvekili") TBMM mv_metadata ile eşleştirir.
# Girdi  : konusmalar.parquet, mv_metadata.parquet
# Çıktı  : konusmalar_metadata.parquet, mv_eslesmeyenler.csv,
#           mv_ambiguous.csv, mv_typo_dogrulanan.csv

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(stringr)
  library(here)
  library(fs)
  library(readr)
  library(tibble)
  library(tidyr)
})

source(here("R", "donem_haritasi.R"))

# ── Normalizasyon yardımcıları ────────────────────────────────────────────────

# R'nin str_to_upper() İngilizce locale'da Türkçe 'i' → 'I' (U+0049) üretiyor,
# oysa Türkçe'de 'i' → 'İ' (U+0130) olmalı. Metadatadaki "Ferit" → "FERIT"
# iken corpus'ta "FERİT" → eşleşme kaçıyor. Önce 'i' → 'İ' değiştiriyoruz.
turkish_upper <- function(x) {
  x |>
    str_replace_all("i", "İ") |>   # i → İ (U+0130)
    str_replace_all("ı", "I") |>   # ı (dotless) → I
    str_to_upper()
}

# Ġ (U+0120) → İ (U+0130) encoding düzeltmesi + Devamla temizliği
# + Circumflex (eski Türkçe yazım: Hakkâri, Şânlıurfa) + boşluklu varyant
sehir_fix <- function(x) {
  x <- str_replace_all(x, "Ġ", "İ")
  x <- str_replace_all(x, "ġ", "İ")
  x[!is.na(x) & str_trim(x) == "Devamla"] <- NA_character_
  x <- turkish_upper(str_trim(x))
  # Circumflex düzeltme: eski yazım Â→A, Û→U, Î→İ
  x <- str_replace_all(x, "Â", "A")
  x <- str_replace_all(x, "Û", "U")
  x <- str_replace_all(x, "Î", "İ")
  # Boşluklu / alternatif şehir adları
  x <- str_replace_all(x, "^ŞANLI URFA$",  "ŞANLIURFA")
  x <- str_replace_all(x, "^K\\.\\s*MARAŞ$", "KAHRAMANMARAŞ")
  x
}

# İsim: parantez ve sonrasını sil, Türkçe büyük harf
norm_isim <- function(x) turkish_upper(str_trim(str_remove(x, "\\s*\\(.*$")))

# Benzersiz 3-lü anahtar: NA güvenli
make_key <- function(isim, sehir, donem) {
  paste(isim, coalesce(sehir, "__NA__"), coalesce(as.character(donem), "__NA__"), sep = "|||")
}

# ── Veri yükleme ──────────────────────────────────────────────────────────────
cat("Veriler yukleniyor...\n")
corpus   <- read_parquet(here("data", "processed", "konusmalar.parquet"))
mv_meta  <- read_parquet(here("data", "processed", "mv_metadata.parquet"))

cat(sprintf("  Corpus  : %d satir\n", nrow(corpus)))
cat(sprintf("  mv_meta : %d satir\n", nrow(mv_meta)))

# Manuel ekleme: TBMM listesinde olmayan ama corpus'ta konusan mv'ler
manuel_path <- here("data/processed/mv_metadata_manuel.csv")
if (file.exists(manuel_path)) {
  manuel <- read_csv(manuel_path, show_col_types = FALSE)
  cat(sprintf("  Manuel mv ekleme: %d kayit\n", nrow(manuel)))
  mv_meta <- bind_rows(mv_meta, manuel)
}

# ── Dönem haritası + normalizasyon ────────────────────────────────────────────
corpus_norm <- corpus |>
  left_join(donem_haritasi, by = "butce_yili") |>
  mutate(
    paran_sehir        = str_extract(konusmaci_ham, "(?<=\\()([^)]+)(?=\\))"),
    isim_norm          = norm_isim(konusmaci_ham),
    sehir_corpus_norm  = sehir_fix(sehir),
    paran_sehir_norm   = sehir_fix(paran_sehir),
    sehir_kaynak = case_when(
      !is.na(sehir_corpus_norm) ~ "corpus",
      !is.na(paran_sehir_norm)  ~ "parantez",
      TRUE                       ~ NA_character_
    ),
    sehir_norm = coalesce(sehir_corpus_norm, paran_sehir_norm),
    lookup_key = make_key(isim_norm, sehir_norm, tbmm_donem)
  )

# İsim alias normalizasyonu - soyadı değişikliği veya takma ad
ALIAS_TABLOSU <- tribble(
  ~eski_norm,    ~yeni_norm,
  "ADİL KURT",  "ADİL ZOZANİ"
)
corpus_norm <- corpus_norm |>
  mutate(
    isim_norm  = coalesce(
      ALIAS_TABLOSU$yeni_norm[match(isim_norm, ALIAS_TABLOSU$eski_norm)],
      isim_norm
    ),
    lookup_key = make_key(isim_norm, sehir_norm, tbmm_donem)
  )

mv_meta_norm <- mv_meta |>
  mutate(
    isim_norm = turkish_upper(str_trim(isim_ham)),
    il_norm   = turkish_upper(str_trim(il))
  )

# ── Unique anahtarlar (sadece mv rolü) ────────────────────────────────────────
mv_corpus <- corpus_norm |> filter(rol == "milletvekili")

unique_keys <- mv_corpus |>
  distinct(isim_norm, sehir_norm, sehir_kaynak, tbmm_donem, lookup_key) |>
  mutate(key_id = row_number())

cat(sprintf("\nUnique (isim, sehir, donem) anahtari: %d\n", nrow(unique_keys)))

# ── Tier 1: Tam eslesme (isim + il + donem) ───────────────────────────────────
cat("\nTier 1 isleniyor...\n")

t1_join <- unique_keys |>
  left_join(
    mv_meta_norm |> select(isim_norm, il_norm, donem, sicil, isim_ham, parti),
    by = c("isim_norm", "sehir_norm" = "il_norm", "tbmm_donem" = "donem"),
    relationship = "many-to-many"
  ) |>
  group_by(key_id) |>
  mutate(n_sicil = n_distinct(sicil, na.rm = TRUE)) |>
  ungroup()

tier1_matched <- t1_join |>
  filter(n_sicil == 1, !is.na(sicil)) |>
  distinct(key_id, .keep_all = TRUE) |>
  transmute(key_id, lookup_key,
            mv_sicil = sicil, mv_isim = isim_ham, mv_parti = parti,
            eslesme_tier = 1L, eslesme_durumu = "matched")

tier1_ambig <- t1_join |>
  filter(n_sicil > 1) |>
  distinct(key_id, .keep_all = TRUE) |>
  transmute(key_id, lookup_key,
            mv_sicil = NA_integer_, mv_isim = NA_character_, mv_parti = NA_character_,
            eslesme_tier = 1L, eslesme_durumu = "ambiguous")

tier1_fail_ids <- unique_keys$key_id[
  !unique_keys$key_id %in% c(tier1_matched$key_id, tier1_ambig$key_id)
]
tier1_fail <- unique_keys |> filter(key_id %in% tier1_fail_ids)

cat(sprintf("  matched   : %d\n  ambiguous : %d\n  fail      : %d\n",
            nrow(tier1_matched), nrow(tier1_ambig), nrow(tier1_fail)))

# ── Tier 2: Isim + donem (sehir gormezden) ────────────────────────────────────
cat("\nTier 2 isleniyor...\n")

t2_join <- tier1_fail |>
  left_join(
    mv_meta_norm |> select(isim_norm, donem, sicil, il_norm, isim_ham, parti),
    by = c("isim_norm", "tbmm_donem" = "donem"),
    relationship = "many-to-many"
  ) |>
  group_by(key_id) |>
  mutate(n_sicil = n_distinct(sicil, na.rm = TRUE)) |>
  ungroup()

tier2_matched <- t2_join |>
  filter(n_sicil == 1, !is.na(sicil)) |>
  distinct(key_id, .keep_all = TRUE) |>
  transmute(key_id, lookup_key,
            mv_sicil = sicil, mv_isim = isim_ham, mv_parti = parti,
            eslesme_tier = 2L, eslesme_durumu = "matched")

# Ambiguous: birden fazla farklı sicil → aynı isimde farklı ilde 2 farklı kişi
tier2_ambig <- t2_join |>
  filter(n_sicil > 1) |>
  group_by(key_id, lookup_key, isim_norm, sehir_norm, tbmm_donem) |>
  summarise(
    cakisan_iller   = paste(sort(unique(il_norm)),  collapse = " / "),
    cakisan_siciller = paste(sort(unique(sicil)),   collapse = " / "),
    .groups = "drop"
  ) |>
  mutate(mv_sicil = NA_integer_, mv_isim = NA_character_, mv_parti = NA_character_,
         eslesme_tier = 2L, eslesme_durumu = "ambiguous")

tier2_fail_ids <- tier1_fail$key_id[
  !tier1_fail$key_id %in% c(tier2_matched$key_id, tier2_ambig$key_id)
]
tier2_fail <- tier1_fail |> filter(key_id %in% tier2_fail_ids)

cat(sprintf("  matched   : %d\n  ambiguous : %d\n  fail      : %d\n",
            nrow(tier2_matched), nrow(tier2_ambig), nrow(tier2_fail)))

# ── Tier 3: Fuzzy isim (il + donem sabit, Levenshtein <= 1) ───────────────────
cat("\nTier 3 isleniyor (Levenshtein <= 1)...\n")

tier3_fail_with_sehir <- tier2_fail |> filter(!is.na(sehir_norm))
cat(sprintf("  Fuzzy icin aday: %d\n", nrow(tier3_fail_with_sehir)))

tier3_results  <- list()
tier3_typo_log <- list()

if (nrow(tier3_fail_with_sehir) > 0) {
  grp_keys <- tier3_fail_with_sehir |> distinct(sehir_norm, tbmm_donem)

  for (i in seq_len(nrow(grp_keys))) {
    g_sehir <- grp_keys$sehir_norm[i]
    g_donem <- grp_keys$tbmm_donem[i]

    c_grp <- tier3_fail_with_sehir |>
      filter(sehir_norm == g_sehir, tbmm_donem == g_donem)
    m_grp <- mv_meta_norm |>
      filter(il_norm == g_sehir, donem == g_donem)

    if (nrow(m_grp) == 0) next

    dist_mat <- adist(c_grp$isim_norm, m_grp$isim_norm)

    for (ci in seq_len(nrow(c_grp))) {
      dists    <- dist_mat[ci, ]
      min_d    <- min(dists)
      if (min_d > 1) next

      best_idx <- which(dists == min_d)
      durumu   <- if (length(best_idx) == 1) "matched" else "ambiguous"
      best     <- m_grp[best_idx[1], ]

      tier3_results[[length(tier3_results) + 1]] <- tibble(
        key_id         = c_grp$key_id[ci],
        lookup_key     = c_grp$lookup_key[ci],
        mv_sicil       = if (durumu == "matched") best$sicil        else NA_integer_,
        mv_isim        = if (durumu == "matched") best$isim_ham     else NA_character_,
        mv_parti       = if (durumu == "matched") best$parti        else NA_character_,
        eslesme_tier   = 3L,
        eslesme_durumu = durumu
      )

      if (durumu == "matched") {
        tier3_typo_log[[length(tier3_typo_log) + 1]] <- tibble(
          korpus_isim = c_grp$isim_norm[ci],
          meta_isim   = best$isim_ham,
          sehir       = g_sehir,
          donem       = g_donem,
          edit_dist   = min_d
        )
      }
    }
  }
}

tier3_df      <- if (length(tier3_results)  > 0) bind_rows(tier3_results)  else tibble()
tier3_typo_df <- if (length(tier3_typo_log) > 0) bind_rows(tier3_typo_log) else tibble()

tier3_matched <- tier3_df |> filter(eslesme_durumu == "matched")
tier3_ambig   <- tier3_df |> filter(eslesme_durumu == "ambiguous")

cat(sprintf("  matched   : %d\n  ambiguous : %d\n",
            nrow(tier3_matched), nrow(tier3_ambig)))

# ── Tier 4: Eslesemeyen ───────────────────────────────────────────────────────
done_ids <- c(tier1_matched$key_id, tier1_ambig$key_id,
              tier2_matched$key_id, tier2_ambig$key_id,
              tier3_matched$key_id, tier3_ambig$key_id)

tier4 <- unique_keys |>
  filter(!key_id %in% done_ids) |>
  transmute(key_id, lookup_key,
            mv_sicil = NA_integer_, mv_isim = NA_character_, mv_parti = NA_character_,
            eslesme_tier = NA_integer_, eslesme_durumu = "unmatched")

cat(sprintf("\nTier 4 unmatched  : %d\n", nrow(tier4)))

# ── Match map: unique_keys → sonuc ────────────────────────────────────────────
match_map <- bind_rows(
  tier1_matched |> select(lookup_key, mv_sicil, mv_isim, mv_parti,
                           eslesme_tier, eslesme_durumu),
  tier1_ambig   |> select(lookup_key, mv_sicil, mv_isim, mv_parti,
                           eslesme_tier, eslesme_durumu),
  tier2_matched |> select(lookup_key, mv_sicil, mv_isim, mv_parti,
                           eslesme_tier, eslesme_durumu),
  tier2_ambig   |> select(lookup_key, mv_sicil, mv_isim, mv_parti,
                           eslesme_tier, eslesme_durumu),
  tier3_matched |> select(lookup_key, mv_sicil, mv_isim, mv_parti,
                           eslesme_tier, eslesme_durumu),
  tier3_ambig   |> select(lookup_key, mv_sicil, mv_isim, mv_parti,
                           eslesme_tier, eslesme_durumu),
  tier4         |> select(lookup_key, mv_sicil, mv_isim, mv_parti,
                           eslesme_tier, eslesme_durumu)
)

# ── Tam corpus'a katıştır ─────────────────────────────────────────────────────
cat("\nTam corpus ile birlestiriliyor...\n")

corpus_out <- corpus_norm |>
  left_join(match_map, by = "lookup_key") |>
  # mv dışı roller: eşleştirme sütunlarını NA yap
  mutate(
    mv_sicil       = if_else(rol == "milletvekili", mv_sicil,       NA_integer_),
    mv_isim        = if_else(rol == "milletvekili", mv_isim,        NA_character_),
    mv_parti       = if_else(rol == "milletvekili", mv_parti,       NA_character_),
    eslesme_tier   = if_else(rol == "milletvekili", eslesme_tier,   NA_integer_),
    eslesme_durumu = if_else(rol == "milletvekili", eslesme_durumu, NA_character_),
    sehir_kaynak   = if_else(rol == "milletvekili", sehir_kaynak,   NA_character_)
  ) |>
  select(-isim_norm, -sehir_corpus_norm, -paran_sehir_norm,
         -paran_sehir, -sehir_norm, -lookup_key)

cat(sprintf("  corpus_out satir: %d\n", nrow(corpus_out)))
stopifnot(nrow(corpus_out) == nrow(corpus))

# ── Kaydet ────────────────────────────────────────────────────────────────────
dir_create(here("data", "processed"), recurse = TRUE)

write_parquet(corpus_out,
              here("data", "processed", "konusmalar_metadata.parquet"))

# Eşleşmeyenler CSV: unique unmatched konusmacılar + konuşma sayısı
mv_unmatched_csv <- mv_corpus |>
  left_join(match_map, by = "lookup_key") |>
  filter(eslesme_durumu == "unmatched") |>
  count(konusmaci_ham, sehir_norm, tbmm_donem, sehir_kaynak,
        name = "konusma_n", sort = TRUE) |>
  rename(sehir = sehir_norm, donem = tbmm_donem)

write_csv(mv_unmatched_csv,
          here("data", "processed", "mv_eslesmeyenler.csv"))

# Ambiguous CSV
ambig_t2 <- if (nrow(tier2_ambig) > 0) {
  tier2_ambig |>
    select(isim_norm, sehir_norm, tbmm_donem,
           cakisan_iller, cakisan_siciller, eslesme_tier) |>
    rename(sehir = sehir_norm, donem = tbmm_donem)
} else tibble()

ambig_t3 <- if (nrow(tier3_ambig) > 0) {
  tier3_ambig |>
    left_join(unique_keys |> select(key_id, isim_norm, sehir_norm, tbmm_donem),
              by = "key_id") |>
    select(isim_norm, sehir_norm, tbmm_donem, eslesme_tier) |>
    rename(sehir = sehir_norm, donem = tbmm_donem) |>
    mutate(cakisan_iller = NA_character_, cakisan_siciller = NA_character_)
} else tibble()

mv_ambiguous_csv <- bind_rows(ambig_t2, ambig_t3)

write_csv(mv_ambiguous_csv,
          here("data", "processed", "mv_ambiguous.csv"))

# Typo CSV
write_csv(tier3_typo_df,
          here("data", "processed", "mv_typo_dogrulanan.csv"))

cat("Dosyalar yazildi.\n")

# ── Konsol özeti ──────────────────────────────────────────────────────────────
n_mv_rows <- nrow(mv_corpus)

tier_counts <- corpus_out |>
  filter(rol == "milletvekili") |>
  count(eslesme_tier, eslesme_durumu) |>
  mutate(oran = round(n / n_mv_rows * 100, 1))

cat("\n=== TIER DAGILIMI (rol==milletvekili satırları) ===\n")
cat(sprintf("Toplam mv satiri: %d\n\n", n_mv_rows))
print(as.data.frame(tier_counts))

cat(sprintf("\nEslesmis (matched)        : %.1f%%\n",
            sum(tier_counts$n[tier_counts$eslesme_durumu == "matched"]) / n_mv_rows * 100))
cat(sprintf("Ambiguous                 : %.1f%%\n",
            sum(tier_counts$n[tier_counts$eslesme_durumu == "ambiguous"], na.rm=TRUE) / n_mv_rows * 100))
cat(sprintf("Unmatched                 : %.1f%%\n",
            sum(tier_counts$n[tier_counts$eslesme_durumu == "unmatched"], na.rm=TRUE) / n_mv_rows * 100))

cat(sprintf("\nEslesmis unique konusmaci : %d\n",
            nrow(unique_keys) - nrow(tier4) -
              nrow(tier2_ambig) - nrow(tier3_ambig) - nrow(tier1_ambig)))
cat(sprintf("Unmatched unique konusmaci: %d\n", nrow(tier4)))
cat(sprintf("Ambiguous unique konusmaci: %d\n",
            nrow(tier1_ambig) + nrow(tier2_ambig) + nrow(tier3_ambig)))

cat("\n=== EN COK KONUSMALI ESLESMEYENLER (Top 20) ===\n")
print(as.data.frame(head(mv_unmatched_csv, 20)))

if (nrow(mv_ambiguous_csv) > 0) {
  cat("\n=== AMBIGUOUS VAKALAR ===\n")
  print(as.data.frame(mv_ambiguous_csv))
}

if (nrow(tier3_typo_df) > 0) {
  cat("\n=== TIER 3 TYPO DUZELTMELERI (ilk 20) ===\n")
  print(as.data.frame(head(tier3_typo_df, 20)))
}
