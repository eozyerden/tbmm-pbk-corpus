# Bakan isimleri arasında Levenshtein fuzzy clustering (typo tespiti)
# Girdi : data/processed/bakan_unvan_isim.csv
# Çıktı : data/processed/bakan_typo_map.csv

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(here)
  library(readr)
  library(tibble)
})

bakan_ozet <- read_csv(here("data", "processed", "bakan_unvan_isim.csv"),
                       show_col_types = FALSE)

# NA isim satırını çıkar
isimler <- bakan_ozet |>
  filter(!is.na(isim), str_length(isim) > 1) |>
  select(isim, toplam_konusma)

isim_vec <- isimler$isim
n <- length(isim_vec)
cat(sprintf("Kanoniklestirilecek benzersiz isim sayisi: %d\n", n))

# ── Pairwise Levenshtein (base R adist) ───────────────────────────────────────
dist_mat <- adist(isim_vec, isim_vec, ignore.case = FALSE)
rownames(dist_mat) <- isim_vec
colnames(dist_mat) <- isim_vec

# Mesafe <= 2 olan çiftler (i < j, kendisi hariç)
pairs <- which(dist_mat <= 2 & lower.tri(dist_mat), arr.ind = TRUE)
cat(sprintf("Mesafe <= 2 olan cift sayisi: %d\n\n", nrow(pairs)))

# ── Union-Find: bağlı bileşenler ──────────────────────────────────────────────
parent <- seq_len(n)
find  <- function(x) { while (parent[x] != x) { parent[x] <<- parent[parent[x]]; x <- parent[x] }; x }
unite <- function(a, b) { pa <- find(a); pb <- find(b); if (pa != pb) parent[pa] <<- pb }

if (nrow(pairs) > 0) {
  for (k in seq_len(nrow(pairs))) unite(pairs[k, 1], pairs[k, 2])
}

cluster_id <- vapply(seq_len(n), find, integer(1))

# ── Kanonik isim = gruptaki en yüksek toplam_konusma ─────────────────────────
isimler <- isimler |> mutate(idx = row_number(), cluster = cluster_id)

typo_map <- isimler |>
  group_by(cluster) |>
  mutate(kanonik_isim = isim[which.max(toplam_konusma)]) |>
  summarise(
    kanonik_isim   = first(kanonik_isim),
    varyantlar     = paste(sort(unique(isim)), collapse = " | "),
    n_varyant      = n_distinct(isim),
    toplam_konusma = sum(toplam_konusma),
    .groups        = "drop"
  ) |>
  arrange(desc(n_varyant), desc(toplam_konusma))

# ── Çıktı ─────────────────────────────────────────────────────────────────────
out_path <- here("data", "processed", "bakan_typo_map.csv")
write_csv(typo_map, out_path)
cat(sprintf("Yazildi: %s  (%d satir)\n\n", out_path, nrow(typo_map)))

# ── Konsol: 20 örnek (en çok varyantlı önce) ──────────────────────────────────
cat("=== Typo cluster ornekleri (ilk 20) ===\n")
top20 <- head(typo_map, 20)
for (i in seq_len(nrow(top20))) {
  cat(sprintf("  [%d varyant | %4d kon]  KANONIK: %-30s  VARYANTLAR: %s\n",
              top20$n_varyant[i], top20$toplam_konusma[i],
              top20$kanonik_isim[i], top20$varyantlar[i]))
}

# ── Özet sayılar ──────────────────────────────────────────────────────────────
cat(sprintf("\n--- OZET ---\n"))
cat(sprintf("Ham benzersiz isim    : %d\n", n))
cat(sprintf("Kanonik isim sayisi   : %d\n", nrow(typo_map)))
cat(sprintf("Typo grubu (>1 varyant): %d\n", sum(typo_map$n_varyant > 1)))
cat(sprintf("Tekil kayit           : %d\n", sum(typo_map$n_varyant == 1)))
