# Changelog

All notable changes to this dataset will be documented in this file.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-XX-XX

### Fixed
- Speaker segmentation failure in budget year 2016. The encoding
  repair now runs before segmentation. Turn count for that year rose
  from 6,745 to 15,260; chair share from 8.6% to 31.2%.
- Footer text leaking into speech records in budget years 2013-2016.
  Two footer templates were not matched by the cleaning rules.
  5,268 turns affected.
- Role classification for institutional representatives. Word-boundary
  assertions failed against Turkish suffixes, and fourteen institutions
  were missing from the pattern list. 806 turns reclassified from
  `milletvekili` to `burokrat`.
- Committee chair for budget year 2015 was unidentified; the lookup
  table gap is now filled. Chair linkage for that year rose from 0.5%
  to 100%.
- Unique MP count was reported as 1,184 in documentation up to
  v1.0.1. That was a count of raw speaker strings, not people; the
  correct figure is 858. See known_issues.md.

### Added
- Chair and minister identity matching, which had not been run against
  the published dataset. Seven columns: `bakan_id`, `bakanlik_adi`,
  `bakanlik_baslangic`, `bakanlik_bitis`, `mv_sicil_bakan`,
  `mv_parti_bakan`, `bakan_eslesme_tier`.
- `scripts/99_validate.R`, a standing validation suite.
- `data/processed/baseline_v1.1.0.csv`, reference metrics.

### Changed
- Corpus total: 223,408 turns to 231,923.
- Linkage is now reported by role: MP 98.0%, chair 100%, minister
  99.3%. The previously headlined 97.5% applied to the MP role only.

### Documented
- Legacy TBMM transcript endpoint behaviour (known_issues.md)
- Unspaced speaker-dash transitions as a background parser limitation

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
