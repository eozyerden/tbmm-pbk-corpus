# Konuşmacı ham isim keşif raporu — Aşama 3a
# Girdi : data/processed/konusmalar.parquet
# Çıktı : reports/04a_konusmaci_kesif.html

suppressPackageStartupMessages({
  library(rmarkdown)
  library(here)
  library(fs)
})

pandoc_dir <- "C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools"
if (fs::dir_exists(pandoc_dir)) {
  rmarkdown::find_pandoc(dir = pandoc_dir, cache = FALSE)
}

parquet_path <- here("data", "processed", "konusmalar.parquet")
if (!fs::file_exists(parquet_path)) {
  stop("konusmalar.parquet bulunamadi — once 06_parse_speeches.R calistirin.")
}

rmd_path  <- here("reports", "04a_konusmaci_kesif.Rmd")
html_path <- here("reports", "04a_konusmaci_kesif.html")

cat("Rapor olusturuluyor...\n")
rmarkdown::render(
  input       = rmd_path,
  output_file = html_path,
  quiet       = TRUE
)
cat(sprintf("Rapor hazir: %s\n", html_path))
