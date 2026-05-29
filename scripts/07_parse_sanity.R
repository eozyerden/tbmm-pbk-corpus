# Konuşma tablosu sanity check raporu üretir.
# Girdi : data/processed/konusmalar.parquet
# Çıktı : reports/02_parse_sanity.html

suppressPackageStartupMessages({
  library(rmarkdown)
  library(here)
  library(fs)
})

# RStudio ile gelen pandoc'u bildir
pandoc_dir <- "C:/Program Files/RStudio/resources/app/bin/quarto/bin/tools"
if (fs::dir_exists(pandoc_dir)) {
  rmarkdown::find_pandoc(dir = pandoc_dir, cache = FALSE)
}

rmd_path  <- here("reports", "02_parse_sanity.Rmd")
html_path <- here("reports", "02_parse_sanity.html")

if (!fs::file_exists(here("data", "processed", "konusmalar.parquet"))) {
  stop("konusmalar.parquet bulunamadi — once 06_parse_speeches.R calistirin.")
}

cat("Rapor olusturuluyor...\n")
rmarkdown::render(
  input       = rmd_path,
  output_file = html_path,
  quiet       = TRUE
)
cat(sprintf("Rapor hazir: %s\n", html_path))
