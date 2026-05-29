# TBMM Budget Committee Discourse Corpus (2009-2025)

[![DOI](https://zenodo.org/badge/DOI/PENDING.svg)](https://doi.org/PENDING)
[![License: MIT](https://img.shields.io/badge/License%20(Code)-MIT-yellow.svg)](LICENSE)
[![License: CC BY 4.0](https://img.shields.io/badge/License%20(Data)-CC%20BY%204.0-lightgrey.svg)](LICENSE)

A structured, machine-readable corpus of the **Turkish Grand National Assembly (TBMM) Plan and Budget Committee (Plan ve Bütçe Komisyonu, PBK)** budget proceedings, covering **17 budget years (2009-2025)** and containing **223,408 speaker turns**.

In Türkiye, the Plan and Budget Committee is the first and most detailed parliamentary stage where the central government budget is deliberated. Each ministry's budget is discussed in depth; ministers, bureaucrats, and members of parliament engage in extensive technical debate. Plenary debate follows in December.

**Türkçe README:** [README_TR.md](README_TR.md)

---

## What's in this corpus

- **223,408 speaker turns** across 294 committee sessions
- **17 budget years** (2009-2025; 2015 absent due to early elections)
- **1,184 unique members of parliament** with linked party, province, and term metadata
- **~100 ministers** (both MP-ministers and appointed technocrats)
- **97.5% metadata linkage rate**

## Quick start

```r
library(arrow)
library(dplyr)

df <- read_parquet("data/processed/konusmalar_metadata.parquet")

# Speeches per budget year
df |> count(butce_yili)

# Word counts by party
df |>
  filter(!is.na(parti)) |>
  group_by(parti) |>
  summarise(total_words = sum(kelime_sayisi)) |>
  arrange(desc(total_words))

# Opposition MP speeches in the 2020 budget hearings
df |>
  filter(butce_yili == 2020, rol == "milletvekili", parti %in% c("CHP", "HDP", "İYİP"))
```

## Repository structure

```
tbmm-pbk-corpus/
├── scripts/            # Pipeline scripts (01-18, numbered in execution order)
├── R/                  # Shared helper functions
├── data/
│   ├── manuel/         # Manual corrections (tracked in git)
│   └── metadata/       # Scraping metadata CSVs (tracked in git)
├── docs/               # Methodology, data dictionary, replication guide
├── CITATION.cff
├── CHANGELOG.md
└── LICENSE
```

Raw PDFs and processed Parquet files are **not stored in this repository**. See "Getting the data" below.

## Getting the data

The processed Parquet files (~160 MB) and raw PDFs (~670 MB) are archived on Zenodo:

> **Zenodo archive:** [DOI placeholder — link will be added at publication]

Download the archive and extract it to the project root. The extracted directories (`data/raw/`, `data/processed/`) are listed in `.gitignore` and will not be committed.

This GitHub repository contains:
- All code (scraping, parsing, metadata matching)
- Manual corrections (small CSVs, versioned as research decisions)
- Scraping metadata (which PDF came from which URL)
- Documentation

To reproduce the corpus from scratch (without the Zenodo download), see [`docs/replication_guide.md`](docs/replication_guide.md).

## Documentation

- [`docs/methodology.md`](docs/methodology.md) — Detailed English methodology (sources, parsing logic, matching algorithm, quality control)
- [`docs/methodology_TR.md`](docs/methodology_TR.md) — Türkçe metodoloji
- [`docs/data_dictionary.md`](docs/data_dictionary.md) — Column-by-column descriptions for all output files
- [`docs/replication_guide.md`](docs/replication_guide.md) — Step-by-step replication instructions
- [`docs/known_issues.md`](docs/known_issues.md) — Known limitations and caveats
- [`docs/coverage_report.md`](docs/coverage_report.md) — Coverage verification (three independent tests)

## Citing this corpus

If you use this corpus in your research, please cite:

```
Özyerden, E. (2026). TBMM Budget Committee Discourse Corpus (2009-2025) [Dataset].
Zenodo. https://doi.org/[PENDING]
```

A machine-readable citation is available in [`CITATION.cff`](CITATION.cff).

## License

See [LICENSE](LICENSE) for full terms.
- **Code** (`scripts/`, `R/`): MIT License
- **Data and documentation** (`data/`, `docs/`, README files, published corpus): CC BY 4.0

## Contact

Emre Özyerden — eozyerden@gmail.com

## Related work

- **Demirtaş, E. (2026).** TBMM Parliamentary Proceedings Corpus with Speaker-Turn Segmentation, 1950-2023. Zenodo. https://doi.org/10.5281/zenodo.19713325 — Plenary proceedings corpus (complementary scope; covers Genel Kurul, not committee stage).
- **Erjavec, T. et al. (2025).** ParlaMint 5.0: A Multilingual Corpus of Parliamentary Debates. CLARIN. — Includes Turkish plenary debates 2011-2021.
