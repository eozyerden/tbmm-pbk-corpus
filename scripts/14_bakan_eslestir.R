suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(readr)
  library(stringr)
  library(tidyr)
  library(here)
})

cat("=== 04g: Bakan Eslestirme ===\n")
cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n\n")

# Turkish uppercase: i->İ, ı->I, then toupper
tr_upper <- function(x) toupper(chartr("iı", "İI", x))

# Onceki calistirmanin ekledigı sutunlar (varsa kaldirilacak)
BAKAN_COLS <- c("bakan_id", "bakanlik_adi", "bakanlik_baslangic", "bakanlik_bitis",
                "mv_sicil_bakan", "mv_parti_bakan", "bakan_eslesme_tier")

# ---- 1. Veri yukle ----
km_raw <- read_parquet(here("data/processed/konusmalar_metadata.parquet"))

# Onceki calistirmadan kalan duplike satirlari temizle (many-to-many hatasindan olabilir)
if (nrow(km_raw) > 210744) {
  cat("! Onceki calistirmadan", nrow(km_raw) - 210744, "fazla satir bulundu — temizleniyor...\n")
  km_raw <- km_raw |>
    group_by(konusma_id) |>
    slice_head(n = 1) |>
    ungroup()
}
km <- km_raw |> select(-any_of(BAKAN_COLS))

bakan_unvan  <- read_csv(here("data/processed/bakan_unvan_isim.csv"),  show_col_types = FALSE)
typo_map     <- read_csv(here("data/processed/bakan_typo_map.csv"),    show_col_types = FALSE)
bakan_manuel <- read_csv(here("data/processed/bakan_manuel.csv"),       show_col_types = FALSE)
mv_meta      <- read_parquet(here("data/processed/mv_metadata.parquet"))

cat("Konusmalar:", nrow(km),
    "| Bakan satiri:", sum(km$rol == "bakan", na.rm = TRUE), "\n\n")

# ---- 2. Varyant -> kanonik lookup ----
typo_long <- typo_map |>
  mutate(vlist = str_split(varyantlar, "\\s*\\|\\s*")) |>
  unnest(vlist) |>
  transmute(varyant = str_squish(vlist), kanonik = kanonik_isim)

# bakan_unvan'daki isimler typo_long'da yoksa identity ekle
extra_kanoniks <- setdiff(bakan_unvan$isim, typo_long$kanonik)
if (length(extra_kanoniks) > 0) {
  typo_long <- bind_rows(
    typo_long,
    tibble(varyant = extra_kanoniks, kanonik = extra_kanoniks)
  )
}

# Uzun varyantlar once (greedy / longest-match)
typo_sorted <- typo_long |> arrange(desc(nchar(varyant)))
vv <- typo_sorted$varyant
kk <- typo_sorted$kanonik

cat("Toplam varyant:", nrow(typo_sorted),
    "| Kanonik:", n_distinct(kk), "\n")

# ---- 3. konusmaci_ham'dan isim + unvan cıkar ----
# str_squish: coklu boslukları (ALI   YERLİKAYA) normalize eder
bakan_unique <- km |>
  filter(rol == "bakan") |>
  distinct(konusmaci_ham) |>
  mutate(ham_sq = str_squish(konusmaci_ham))

match_fn <- function(ham) {
  for (i in seq_along(vv)) {
    if (endsWith(ham, vv[i])) {
      unvan <- str_trim(substr(ham, 1L, nchar(ham) - nchar(vv[i])))
      return(list(kanonik = kk[i], unvan_raw = unvan))
    }
  }
  list(kanonik = NA_character_, unvan_raw = NA_character_)
}

# FIX: Farkli ham → aynı ham_sq durumunu onle (coklu bosluk varyantlari).
# distinct(ham_sq) ile unique squished degerler uzerinde calis, sonra
# join many-to-one olur.
bakan_unique <- bakan_unique |> distinct(ham_sq)

cat("Isim + unvan cikariyor (", nrow(bakan_unique), "benzersiz ham_sq)...\n")
res <- lapply(bakan_unique$ham_sq, match_fn)
bakan_unique$kanonik_isim <- sapply(res, `[[`, "kanonik")
bakan_unique$unvan_raw    <- sapply(res, `[[`, "unvan_raw")

# Bakanlik adini cikar: " BAKANI?" kaldir
# "\\s+BAKANI?$" → bosluk gerektiriyor, BAŞBAKAN/CUMHURBAŞKANI etkilenmiyor
bakan_unique <- bakan_unique |>
  mutate(
    bakanlik_ham = str_trim(str_remove(unvan_raw, "\\s+BAKANI?$"))
  )

n_no_match <- sum(is.na(bakan_unique$kanonik_isim))
cat("\nEslesmeyenler (", n_no_match, "):\n")
print(bakan_unique |> filter(is.na(kanonik_isim)) |> pull(ham_sq))

# ---- 4. mv-bakan eslestirme ----
# isim_ham "Ad SOYAD" formatinda → tr_upper ile tam buyuk harfe
mv_upper_lookup <- mv_meta |>
  mutate(isim_upper = tr_upper(isim_ham)) |>
  group_by(isim_upper) |>
  slice_max(donem, n = 1, with_ties = FALSE) |>
  ungroup() |>
  transmute(isim_upper, mv_sicil_bakan = sicil,
            mv_il_bakan = il, mv_parti_bakan = parti)

bakan_unique <- bakan_unique |>
  left_join(mv_upper_lookup, by = c("kanonik_isim" = "isim_upper"))

cat("\nmv-bakan eslesen (benzersiz isim):",
    sum(!is.na(bakan_unique$mv_sicil_bakan)), "\n")

# ---- 5. Atanmış bakan lookup ----
atanmis <- bakan_manuel |>
  mutate(bakan_id = sprintf("atanan_%03d", row_number())) |>
  transmute(
    kanonik_isim         = isim_kanonik,
    bakan_id,
    bakanlik_adi_atanmis = bakanlik,
    bakanlik_baslangic   = baslangic_tarihi,
    bakanlik_bitis       = bitis_tarihi,
    bakan_parti          = parti
  )

cat("Atanmis bakan (lookup):", nrow(atanmis), "\n\n")

# ---- 6. Ana tabloya uygula ----
km_bakan <- km |>
  filter(rol == "bakan") |>
  mutate(ham_sq = str_squish(konusmaci_ham)) |>
  left_join(
    bakan_unique |> select(ham_sq, kanonik_isim, bakanlik_ham,
                            mv_sicil_bakan, mv_il_bakan, mv_parti_bakan),
    by = "ham_sq",
    relationship = "many-to-one"  # ham_sq distinct(ham_sq) ile tek satirli
  ) |>
  select(-ham_sq)

# Atanmış join (many-to-one: her kanonik_isim atanmis'ta en fazla 1 kez)
km_bakan <- km_bakan |>
  left_join(atanmis, by = "kanonik_isim", relationship = "many-to-one")

# ---- 7. Tarih uyum kontrolu (sadece atanmış) ----
km_bakan <- km_bakan |>
  mutate(
    tarih_uyumlu = case_when(
      is.na(bakan_id)           ~ NA,
      is.na(tarih)              ~ NA,
      is.na(bakanlik_baslangic) ~ NA,
      tarih >= bakanlik_baslangic &
        (is.na(bakanlik_bitis) | tarih <= bakanlik_bitis) ~ TRUE,
      TRUE ~ FALSE
    )
  )

# ---- 8. Eslesme tier ----
km_bakan <- km_bakan |>
  mutate(
    bakan_eslesme_tier = case_when(
      !is.na(mv_sicil_bakan)                            ~ "mv-bakan",
      !is.na(bakan_id) & !is.na(tarih_uyumlu) & !tarih_uyumlu ~ "rol_tarih_uyumsuz",
      !is.na(bakan_id)                                  ~ "atanmış",
      TRUE                                              ~ "eslesemedi"
    ),
    bakanlik_adi = coalesce(bakanlik_ham, bakanlik_adi_atanmis)
  )

cat("Bakan tier dagilimi:\n")
print(km_bakan |> count(bakan_eslesme_tier, sort = TRUE))

# ---- 9. konusmalar_metadata.parquet guncelle ----
new_bakan_cols <- km_bakan |>
  select(konusma_id, bakan_id, bakanlik_adi,
         bakanlik_baslangic, bakanlik_bitis,
         mv_sicil_bakan, mv_parti_bakan,
         bakan_eslesme_tier)

km_updated <- km |>
  left_join(new_bakan_cols, by = "konusma_id")

cat("\nGuncellenmis parquet sutun sayisi:", ncol(km_updated), "\n")
write_parquet(km_updated, here("data/processed/konusmalar_metadata.parquet"))
cat("konusmalar_metadata.parquet yazildi.\n\n")

# ---- 10. Kayit dosyalari ----
eslesemedi_df <- km_bakan |>
  filter(bakan_eslesme_tier == "eslesemedi") |>
  count(konusmaci_ham, sort = TRUE)

if (nrow(eslesemedi_df) > 0) {
  write_csv(eslesemedi_df, here("data/processed/bakan_eslesmeyenler.csv"))
  cat("bakan_eslesmeyenler.csv:", nrow(eslesemedi_df), "benzersiz isim\n")
}

uyumsuz_df <- km_bakan |>
  filter(bakan_eslesme_tier == "rol_tarih_uyumsuz") |>
  select(konusma_id, konusmaci_ham, tarih, bakan_id,
         bakanlik_adi, bakanlik_baslangic, bakanlik_bitis)

if (nrow(uyumsuz_df) > 0) {
  write_csv(uyumsuz_df, here("data/processed/bakan_rol_tarih_uyumsuz.csv"))
  cat("bakan_rol_tarih_uyumsuz.csv:", nrow(uyumsuz_df), "satir\n")
}

# ---- 11. FINAL OZET RAPOR ----
cat("\n", strrep("=", 55), "\n", sep = "")
cat("ASAMA 3 — FİNAL OZET RAPOR\n")
cat(strrep("=", 55), "\n\n", sep = "")

cat("1. Toplam konusma:", nrow(km_updated), "\n\n")

cat("2. Rol bazinda konusma ve esleme oranlari:\n")
mv_total  <- sum(km_updated$rol == "milletvekili", na.rm = TRUE)
mv_match  <- sum(!is.na(km_updated$mv_sicil) & km_updated$rol == "milletvekili", na.rm = TRUE)
bsk_total <- sum(km_updated$rol == "baskan", na.rm = TRUE)
bsk_match <- sum(!is.na(km_updated$mv_sicil) & km_updated$rol == "baskan", na.rm = TRUE)
bak_total <- sum(km_updated$rol == "bakan", na.rm = TRUE)
bak_match <- sum(km_updated$rol == "bakan" &
                   !is.na(km_updated$bakan_eslesme_tier) &
                   km_updated$bakan_eslesme_tier != "eslesemedi", na.rm = TRUE)
bur_total <- sum(km_updated$rol == "burokrat", na.rm = TRUE)

cat(sprintf("   milletvekili : %7d konusma  | esleme %%%.1f\n",
            mv_total,  if (mv_total  > 0) mv_match  / mv_total  * 100 else 0))
cat(sprintf("   baskan       : %7d konusma  | esleme %%%.1f\n",
            bsk_total, if (bsk_total > 0) bsk_match / bsk_total * 100 else 0))
cat(sprintf("   bakan        : %7d konusma  | esleme %%%.1f\n",
            bak_total, if (bak_total > 0) bak_match / bak_total * 100 else 0))
cat(sprintf("   burokrat     : %7d konusma  | (analiz disi)\n\n", bur_total))

cat("3. Genel kapsama (parti veya bakanlik veya baskanlik bilgisi olan):\n")
tam_meta_n <- km_updated |>
  filter(
    (rol == "milletvekili" & !is.na(mv_parti)) |
    (rol == "baskan"       & !is.na(mv_sicil)) |
    (rol == "bakan"        & !is.na(bakan_eslesme_tier) &
       bakan_eslesme_tier != "eslesemedi")
  ) |>
  nrow()
cat(sprintf("   %d konusma tam metadata (%%%.1f toplam)\n\n",
            tam_meta_n, tam_meta_n / nrow(km_updated) * 100))

cat("4. Bakan esleme detayi:\n")
tier_n <- km_updated |>
  filter(rol == "bakan") |>
  count(bakan_eslesme_tier, sort = TRUE)
print(tier_n)

cat("\n   Eslesemedi — top 10:\n")
if (nrow(eslesemedi_df) > 0) print(head(eslesemedi_df, 10)) else cat("   (yok)\n")

cat("\n5. Bilinen eksiklikler:\n")
cat("   - Mv-bakanlar icin bakanlik_baslangic/bitis dolu degil")
cat(" (Asama 4'te mv_bakan_donemleri.csv eklenecek)\n")
cat("   - Tarih bilgisi olmayan bakan satirlari tarih_uyumlu=NA ile atanmis sayildi\n")
if (nrow(uyumsuz_df) > 0)
  cat(sprintf("   - %d konusma rol-tarih uyumsuz (bakan_rol_tarih_uyumsuz.csv)\n",
              nrow(uyumsuz_df)))

cat("\n", strrep("=", 55), "\n", sep = "")
cat("ASAMA 3 KAPANDI.\n")
cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
