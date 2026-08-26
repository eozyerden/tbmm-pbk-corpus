# Changelog

All notable changes to this dataset will be documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Documented
- Speaker segmentation failure in 2016 SBB transcripts (known_issues.md)
- Legacy TBMM transcript endpoint behaviour (known_issues.md)

### Planned
- Re-parse of 13 affected 2016 SBB PDFs with corrected processing order

## [1.0.1] - 2026-05-30

### Added
- Author ORCID identifier (0000-0003-3577-4236) in CITATION.cff, README files
- Initial publication on Zenodo (2026-05-30)
- DOI (concept): 10.5281/zenodo.20457565
- DOI (this version): 10.5281/zenodo.20457566
- Data files uploaded to Zenodo (processed parquet + raw PDFs, 394 MB)

## [1.0.0] - 2026-XX-XX

### Added
- Initial public release
- 17 budget years (2009-2025) of TBMM Plan and Budget Committee proceedings
- 223,408 speaker turns
- 294 PDF source documents (196 SBB + 98 TBMM legacy)
- MP roster covering TBMM terms 23-28 (3,329 records)
- Manual MP corrections (Aslanoğlu 24th term, Kazım Kurt 24th term)
- Adil Kurt → Adil Zozani alias mapping
- Complete metadata linkage (97.5% coverage)

### Known Issues
- Erol Akbulut and similar institutional representatives (~3,271 rows) misclassified as MPs
- 2018 PDF parsing required Poppler workaround (PDF 1.6 + non-linearized)
- Single date discrepancy in 20211126 (source document error)
