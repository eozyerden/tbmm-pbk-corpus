# TBMM Plan and Budget Committee Discourse Corpus (2009-2025)

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.20457565.svg)](https://doi.org/10.5281/zenodo.20457565)
[![License: MIT](https://img.shields.io/badge/License%20(Code)-MIT-yellow.svg)](LICENSE)
[![License: CC BY 4.0](https://img.shields.io/badge/License%20(Data)-CC%20BY%204.0-lightgrey.svg)](LICENSE)
[![ORCID](https://img.shields.io/badge/ORCID-0000--0003--3577--4236-A6CE39?logo=orcid&logoColor=white)](https://orcid.org/0000-0003-3577-4236)

A structured, machine-readable corpus of the **Turkish Grand National Assembly (TBMM) Plan and Budget Committee (Plan ve Bütçe Komisyonu, PBK)** budget proceedings, covering **17 budget years (2009-2025)** and containing **231,923 speaker turns**.

In Türkiye, the Plan and Budget Committee is the first and most detailed parliamentary stage where the central government budget is deliberated. Each ministry's budget is discussed in depth; ministers, bureaucrats, and members of parliament engage in extensive technical debate. Plenary debate follows in December.

**Türkçe README:** [README_TR.md](README_TR.md)

---

## What's in this corpus

- **231,923 speaker turns** across 294 source PDFs
- **17 budget years** (2009-2025). Note: budget deliberations did not take place in calendar year 2015 due to early elections; however, the 2015 budget year is included in the corpus (deliberated in late 2014).
- **858 unique MPs** (identified by TBMM permanent identifier) with linked party, province, and term metadata
- **98 ministers** — 80 MP-ministers, 18 appointed technocrats
- **6 committee chairs** (plus 13 Speakers and Deputy Speakers of the Assembly who presided occasionally) across the corpus period
- **Identity linkage by role: MP 98.0%, chair 100%, minister 99.3%** (see [docs/data_dictionary.md](docs/data_dictionary.md))

> **Data quality.** Version 1.1.0 corrects five defects present in
> v1.0.1, affecting speaker segmentation in budget year 2016, footer
> text in 2013-2016, role classification of institutional
> representatives, chair identification for 2015, and a misreported
> unique MP count (1,184 was a count of raw speaker strings; the
> correct figure is 858). See the
> [quality note](docs/quality_note_v1.1.0.md),
> [CHANGELOG.md](CHANGELOG.md) and
> [docs/known_issues.md](docs/known_issues.md). Users of v1.0.1
> should migrate.

## Quick start

```r
library(arrow)
library(dplyr)

df <- read_parquet("data/processed/konusmalar_metadata.parquet")

# Speeches per budget year
df |> count(butce_yili)

# Word counts by party (party affiliation is in `mv_parti`, not `parti`)
df |>
  filter(!is.na(mv_parti)) |>
  group_by(mv_parti) |>
  summarise(total_words = sum(kelime_sayisi)) |>
  arrange(desc(total_words))

# Opposition MP speeches in the 2020 budget hearings
df |>
  filter(butce_yili == 2020, rol == "milletvekili", mv_parti %in% c("CHP", "HDP", "İYİP"))
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

The processed corpus and the raw source PDFs are published as two separate archives on Zenodo (record [22150634](https://zenodo.org/records/22150634)):

- **Processed data** — `tbmm-pbk-corpus-data-v1.1.0.zip`: 76.0 MB as downloaded (compressed); ~86 MB once extracted. Contains `konusmalar_metadata.parquet`, `mv_metadata.parquet`, `baseline_v1.1.0.csv`, a data dictionary, and a license file.
- **Raw source PDFs** — `tbmm-pbk-corpus-raw-v1.1.0.zip`: 320.5 MB as downloaded (compressed).

> **Zenodo archive:** [10.5281/zenodo.20457565](https://doi.org/10.5281/zenodo.20457565) (concept DOI, always resolves to the latest version). Current version: **v1.1.0** — version-specific DOI [10.5281/zenodo.22150634](https://doi.org/10.5281/zenodo.22150634).

Both zip files extract **flat** (no `data/processed/` or `data/raw/` subfolders inside the archive). After extracting, create `data/processed/` and `data/raw/` if they do not already exist and move the files there, so paths match this README and the pipeline scripts. Both directories are listed in `.gitignore` and will not be committed.

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
- [`docs/quality_note_v1.1.0.md`](docs/quality_note_v1.1.0.md) — Quality note for v1.1.0: the five corrected defects, identity matching, and the validation suite
- [`docs/coverage_report.md`](docs/coverage_report.md) — Coverage verification (three independent tests)

## Citing this corpus

If you use this corpus in your research, please cite:

```
Özyerden, E. (2026). TBMM Plan and Budget Committee Discourse Corpus [Dataset].
Zenodo. https://doi.org/10.5281/zenodo.20457565
```

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.20457565.svg)](https://doi.org/10.5281/zenodo.20457565)

The citation above uses the concept DOI (10.5281/zenodo.20457565), which always resolves to the latest version. To cite the exact version used in your analysis, cite v1.1.0 directly: DOI [10.5281/zenodo.22150634](https://doi.org/10.5281/zenodo.22150634).

A machine-readable citation is available in [`CITATION.cff`](CITATION.cff).

## License

See [LICENSE](LICENSE) for full terms.
- **Code** (`scripts/`, `R/`): MIT License
- **Data and documentation** (`data/`, `docs/`, README files, published corpus): CC BY 4.0

## Contact
Emre Özyerden ([ORCID: 0000-0003-3577-4236](https://orcid.org/0000-0003-3577-4236)) — eozyerden@gmail.com

## Related work

- **Demirtaş, E. (2026).** TBMM Parliamentary Proceedings Corpus with Speaker-Turn Segmentation, 1950-2023. Zenodo. https://doi.org/10.5281/zenodo.19713325 — Plenary proceedings corpus (complementary scope; covers Genel Kurul, not committee stage).
- **Erjavec, T. et al. (2025).** ParlaMint 5.0: A Multilingual Corpus of Parliamentary Debates. CLARIN. — Includes Turkish plenary debates 2011-2021.
