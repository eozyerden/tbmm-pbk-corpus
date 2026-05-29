# Data Directory

This directory contains:

## `manuel/` — Manual corrections (small CSVs, tracked in git)

Manual additions and corrections necessary for replication. These files are version-controlled because they represent research decisions, not raw data:

- `mv_metadata_manuel.csv` — Members of parliament not present in TBMM's official roster (e.g., F.M. Aslanoğlu's 24th term, K. Kurt's 24th term)
- `bakan_manuel.csv` — Non-MP ministers (technocrats appointed by the Council of Ministers)
- `atanmis_bakanlar_manuel.csv` — Same as above with different naming (legacy)

## `metadata/` — Scraping metadata (CSVs, tracked in git)

Record of which PDF was downloaded from which source URL. Useful for replication:

- `sbb_metadata.csv` — SBB-sourced PDFs (2016-2025)
- `owa_metadata.csv` — TBMM legacy-system PDFs (2009-2015)
- `owa_butce_ids.csv` — TBMM URL IDs used to fetch OWA data

## `raw/` and `processed/` — Not in git, download from Zenodo

These directories will be populated when you run the pipeline or download data from the Zenodo archive:

- `raw/pdf/sbb/` — 196 SBB PDF files
- `raw/pdf/owa/` — 98 TBMM legacy PDFs
- `raw/txt/` — Plain text extracts
- `processed/konusmalar_metadata.parquet` — Main corpus (with metadata)
- `processed/mv_metadata.parquet` — TBMM MP roster

To get the full data, see [Zenodo archive: DOI placeholder].
