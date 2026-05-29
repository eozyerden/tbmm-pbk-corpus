# Bakan konusmaci_ham -> unvan + isim ayrıştırma
# Girdi : data/processed/konusmalar.parquet
# Çıktı : data/processed/bakan_unvan_isim.csv

suppressPackageStartupMessages({
  library(arrow)
  library(dplyr)
  library(stringr)
  library(here)
  library(readr)
})

k     <- read_parquet(here("data", "processed", "konusmalar.parquet"))
bakan <- k |> filter(rol == "bakan")

# konuşma sayısı: her benzersiz ham için
ham_konusma <- bakan |>
  count(konusmaci_ham, name = "konusma_n")

uniq_ham <- unique(bakan$konusmaci_ham)
uniq_ham <- uniq_ham[!is.na(uniq_ham)]

# ── Parse: greedy regex, son BAKANI/YARDIMCISI/YARDIMCI split ─────────────────
# Sıra önemli: YARDIMCISI önce (YARDIMCI içine gömülü olmasın)
split_pattern <- "^(.+(?:BAKANI|YARDIMCISI|YARDIMCI))\\s+(.+)$"

parse_ham <- function(x) {
  m <- str_match(x, split_pattern)
  if (!is.na(m[1, 1])) {
    list(unvan = str_trim(m[1, 2]), isim = str_trim(m[1, 3]))
  } else {
    # split edilemeyen (örn. sadece "SAĞLIK BAKANI FAHRETTİN" gibi eksik)
    list(unvan = x, isim = NA_character_)
  }
}

parsed <- lapply(uniq_ham, parse_ham)

bakan_df <- tibble(
  konusmaci_ham = uniq_ham,
  unvan         = sapply(parsed, `[[`, "unvan"),
  isim          = sapply(parsed, `[[`, "isim")
) |>
  left_join(ham_konusma, by = "konusmaci_ham")

# ── İsim bazında özet ─────────────────────────────────────────────────────────
bakan_ozet <- bakan_df |>
  group_by(isim) |>
  summarise(
    n_unvan        = n_distinct(unvan),
    unvanlar       = paste(sort(unique(unvan)), collapse = " | "),
    toplam_konusma = sum(konusma_n),
    .groups        = "drop"
  ) |>
  arrange(desc(n_unvan), desc(toplam_konusma))

# ── Çıktı ─────────────────────────────────────────────────────────────────────
out_path <- here("data", "processed", "bakan_unvan_isim.csv")
write_csv(bakan_ozet, out_path)
cat(sprintf("Yazildi: %s  (%d satir)\n\n", out_path, nrow(bakan_ozet)))

# ── Konsol özeti: en çok unvanı olan 30 isim ──────────────────────────────────
cat("=== En cok unvana sahip 30 bakan ismi ===\n")
top30 <- bakan_ozet |>
  head(30) |>
  mutate(unvan_ozet = ifelse(
    nchar(unvanlar) > 80,
    paste0(substr(unvanlar, 1, 77), "..."),
    unvanlar
  ))

for (i in seq_len(nrow(top30))) {
  cat(sprintf("  [%2d unvan | %4d kon]  %-30s  %s\n",
              top30$n_unvan[i], top30$toplam_konusma[i],
              top30$isim[i], top30$unvan_ozet[i]))
}

# ── Parse edilemeyen kayıtlar ──────────────────────────────────────────────────
parse_fail <- bakan_df |> filter(is.na(isim))
if (nrow(parse_fail) > 0) {
  cat(sprintf("\nParse edilemeyen kayit: %d\n", nrow(parse_fail)))
  print(select(parse_fail, konusmaci_ham, konusma_n))
}
