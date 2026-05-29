# Replication Guide

This guide explains how to reproduce the TBMM PBK Budget Discourse Corpus from scratch. The pipeline is implemented entirely in R and runs on Windows (tested on Windows 10 with R 4.6.0).

---

## 1. Prerequisites

### Software

| Requirement | Version | Notes |
|---|---|---|
| R | ≥ 4.5 | Tested on 4.6.0 |
| RStudio (optional) | any | For interactive use |
| Poppler `pdftotext` | any recent | **Required only for Step 5** (2018 PDFs) |

**Installing Poppler on Windows:** The easiest route is via [MiKTeX](https://miktex.org/), which includes `pdftotext.exe`. Alternatively, download a standalone Poppler Windows build. After installation, note the full path to `pdftotext.exe` — you will need it in Step 5.

### R packages

All package versions are locked in `renv.lock`. After cloning the repository, run:

```r
install.packages("renv")
renv::restore()
```

Key packages: `pdftools`, `rvest`, `httr2`, `arrow`, `dplyr`, `stringr`, `readr`, `here`, `fs`, `furrr`

---

## 2. Repository Setup

```bash
git clone https://github.com/eozyerden/tbmm-pbk-corpus.git
cd tbmm-pbk-corpus
```

Open an R session with the project root as the working directory (open the `.Rproj` file in RStudio, or set `setwd()` manually). Run `renv::restore()`.

---

## 3. Download Raw Data from Zenodo

If you want to start from the processed Parquet files (skipping scraping and parsing):

1. Download the Zenodo archive: [DOI placeholder]
2. Extract to the project root. The archive contains:
   - `data/raw/pdf/sbb/` — 196 SBB PDFs (~580 MB)
   - `data/raw/pdf/owa/` — 98 OWA PDFs (~90 MB)
   - `data/raw/txt/` — plain text extracts of all PDFs
   - `data/processed/konusmalar_metadata.parquet` — main corpus
   - `data/processed/mv_metadata.parquet` — MP roster

If you want to reproduce from scratch, proceed with Steps 4-11 below.

---

## 4. Run the Pipeline

Scripts are numbered in execution order. Each script is self-contained: it reads from `data/` and writes to `data/`. All paths use `here::here()` relative to the project root.

> **Scraping scripts (01-03) make HTTP requests to official government servers.** Rate limiting is enforced (1 request/second). Full scraping takes several hours. If you have the PDFs from Zenodo, skip to Step 7.

### Step 4 — Scrape SBB PDFs (optional if using Zenodo)

```r
source(here::here("scripts", "01_scrape_sbb.R"))
```

Downloads 196 PDFs from SBB to `data/raw/pdf/sbb/`. Resume-safe: skips existing files.

Expected output: `data/raw/pdf/sbb/*.pdf` (196 files, ~580 MB total)

---

### Step 5 — Collect OWA session IDs (optional if using Zenodo)

```r
source(here::here("scripts", "02_collect_owa_ids.R"))
```

Queries TBMM OWA for Plan and Budget Committee session IDs. Writes `data/metadata/owa_butce_ids.csv`.

---

### Step 6 — Scrape OWA PDFs (optional if using Zenodo)

```r
source(here::here("scripts", "03_scrape_owa.R"))
```

Downloads 98 PDFs to `data/raw/pdf/owa/`. Resume-safe.

---

### Step 7 — Extract text from SBB PDFs

```r
source(here::here("scripts", "04_extract_text_sbb.R"))
```

Uses `pdftools::pdf_text()` to extract text from all PDFs **except** the 16 problematic 2018 files (handled in Step 8). Writes UTF-8 `.txt` files to `data/raw/txt/`.

Expected output: ~278 `.txt` files

---

### Step 8 — Extract text from 2018 PDFs (Poppler)

**Before running:** Set the path to `pdftotext.exe` at the top of the script:

```r
# In 05_extract_text_2018_poppler.R, line ~15:
poppler_path <- "C:/Program Files/MiKTeX/miktex/bin/x64/pdftotext.exe"
# Adjust to your actual Poppler installation path
```

```r
source(here::here("scripts", "05_extract_text_2018_poppler.R"))
```

Processes the 16 non-linearized PDF 1.6 files that hang `pdftools`. Writes 16 additional `.txt` files.

---

### Step 9 — Parse speeches

```r
source(here::here("scripts", "06_parse_speeches.R"))
```

Segments all plain text files into speaker turns. Applies role detection, name normalization, and `butce_yili` assignment.

Expected output: `data/processed/konusmalar.parquet` (~223,408 rows)
Runtime: 5-15 minutes depending on hardware.

---

### Step 10 — Parse sanity check (optional)

```r
source(here::here("scripts", "07_parse_sanity.R"))
```

Generates an HTML diagnostic report. Checks role distribution, year coverage, speech length distribution. Not required for replication; useful for diagnosing parse issues.

---

### Step 11 — Speaker exploration (optional)

```r
source(here::here("scripts", "08_konusmaci_kesif.R"))
```

Exploratory report on unique speaker names, typo clusters, and potential parse artifacts.

---

### Steps 12-18 — Metadata pipeline

Run in order. Each script reads from the previous step's output.

```r
source(here::here("scripts", "09_bakan_ayristir.R"))      # Minister title/name separation
source(here::here("scripts", "10_bakan_typo_temizlik.R")) # Minister name typo clustering
source(here::here("scripts", "11_tbmm_mv_scrape.R"))      # Scrape TBMM MP roster
source(here::here("scripts", "12_mv_eslestirme.R"))       # MP matching (main linkage step)
source(here::here("scripts", "13_baskan_eslestir.R"))     # Committee chair matching
source(here::here("scripts", "14_bakan_eslestir.R"))      # Minister matching
source(here::here("scripts", "15_hacim_dogrulama.R"))     # Volume validation
```

Expected output after Step 14: `data/processed/konusmalar_metadata.parquet` (main corpus with full metadata)

---

### Steps 16-17 — Encoding diagnostics and fix

```r
source(here::here("scripts", "16_encoding_tani.R"))   # Identify 2016 encoding issue
source(here::here("scripts", "17_encoding_duzelt.R")) # Apply character-level corrections
```

These scripts identify and fix the 2016 PDF encoding corruption (Ģ → ş, ġ → Ş, Ġ → İ). Step 17 updates `konusmalar_metadata.parquet` in place.

---

### Step 18 — Coverage verification

```r
source(here::here("scripts", "18_kapsama_analizi.R"))
```

Three-part coverage check: session-number sequencing, ministry detection, volume sanity. Produces `reports/18_kapsama_analizi_raporu.md`.

---

## 5. Expected Outputs

After a full pipeline run:

| File | Rows/Size | Description |
|---|---|---|
| `data/processed/konusmalar_metadata.parquet` | 223,408 rows | Main corpus |
| `data/processed/mv_metadata.parquet` | 3,331 rows | MP roster (TBMM + manual) |
| `data/processed/sbb_metadata.csv` | 196 rows | SBB PDF download log |
| `data/processed/owa_metadata.csv` | 98 rows | OWA PDF download log |
| `data/processed/bakan_unvan_isim.csv` | ~113 rows | Canonical minister names |
| `data/processed/mv_listesi.csv` | ~3,329 rows | Raw TBMM MP roster |
| `data/processed/baskan_eslestirme.csv` | ~26 rows | Chair name lookup results |

---

## 6. Troubleshooting

**`pdftools::pdf_text()` hangs on a PDF**
This is the PDF 1.6 / non-linearized issue. Run `05_extract_text_2018_poppler.R` for those files. If it happens for a file not in the 2018 season, file an issue with the filename.

**MP match rate lower than expected**
Check whether the TBMM OWA scraper captured all terms. Run `11_tbmm_mv_scrape.R` again and compare `mv_listesi.csv` row count to the expected ~3,329.

**`here()` returns wrong path**
Ensure your R session is started from the project root. The project root is identified by the presence of `renv.lock`. Run `here::here()` in the console; it should return the repo root directory.

**`renv::restore()` fails**
Some packages require compilation. On Windows, install [Rtools](https://cran.r-project.org/bin/windows/Rtools/) matching your R version.

**`arrow` package not loading**
Arrow on Windows occasionally needs a manual install: `install.packages("arrow", repos = "https://apache.r-universe.dev")`.

---

## 7. Partial Replication

If you only want to reproduce a specific stage:

- **Re-run metadata matching only:** Start from Step 12 using the `konusmalar.parquet` from Zenodo.
- **Re-run encoding fix only:** Start from Step 16.
- **Re-run coverage verification only:** Start from Step 18.

Each script checks for the existence of its input file and stops with an informative error message if it is missing.
