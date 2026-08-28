# Methodology

## 1. Overview

This corpus was constructed from the official verbatim transcripts of the **TBMM Plan and Budget Committee (Plan ve Bütçe Komisyonu, PBK)**, the primary parliamentary venue for detailed deliberation of Turkey's central government budget. Each fiscal year, ministries present their budgets to the PBK one at a time; ministers, senior bureaucrats, and committee members engage in extended technical debate before the budget proceeds to a plenary vote in December.

The construction pipeline consists of six sequential stages:

```
1. SCRAPING         — Download PDFs from two official sources
2. TEXT EXTRACTION  — Convert PDFs to plain text
3. PARSING          — Segment text into speaker turns
4. METADATA LINKAGE — Match speakers to MP roster, minister list, committee chairs
5. QUALITY CONTROL  — Encoding correction, coverage verification
6. OUTPUT           — Write structured Parquet corpus
```

The entire pipeline is implemented in R and is fully reproducible from the raw PDFs. See [`replication_guide.md`](replication_guide.md) for step-by-step instructions.

---

## 2. Data Sources

Two distinct archival systems were used, corresponding to different periods:

### Source A: SBB (Strateji ve Bütçe Başkanlığı), 2016-2025

The Presidency of Strategy and Budget publishes PBK budget hearing transcripts on its website as PDF files. These are the official, high-quality documents for the modern period.

- **URL:** `https://www.sbb.gov.tr/tbmm-plan-ve-butce-komisyonu-butce-tutanaklari/`
- **Documents:** 196 PDFs
- **Period covered:** Budget years 2016-2025 (sessions held October-November 2015 through November 2024)
- **Format:** Selectable-text PDF, modern Poppler-compatible, UTF-8 encoded

### Source B: TBMM OWA (legacy system), 2009-2015

For the earlier period, transcripts are available through TBMM's legacy document retrieval system (Oracle Web Application, OWA), which has since been deprecated.

- **URL pattern:** `https://www.tbmm.gov.tr/Tutanaklar/TutanakGoster/{ID}`
- **Documents:** 98 PDFs
- **Period covered:** Budget years 2009-2015 (sessions held November 2008 through November 2014)
- **Format:** Selectable-text PDF; shorter page counts than SBB documents (median 90 vs. 138 pages)

### Coverage gap

No PBK budget hearing transcripts are available before budget year 2009. TBMM's OWA system does not contain records for legislative years 1 and 2 of the 23rd parliamentary term (which would correspond to the 2008 budget deliberations). The 2015 calendar year has no hearings because early elections disrupted the normal October-November budget window; the 2016 budget was debated in January-February 2016.

---

## 3. Scraping Methodology

### 3.1 SBB (Source A)

The SBB page lists PDF links for each budget year. The scraper (`01_scrape_sbb.R`) performs the following:

1. Fetches the SBB index page via `httr2`
2. Extracts all PDF hyperlinks using `rvest`
3. Downloads each PDF with a 1-second inter-request delay
4. Skips files already present (resume-safe)
5. Logs each download with timestamp, file size, and HTTP status

### 3.2 TBMM OWA (Source B)

The OWA system does not expose a browseable index. Documents are identified by integer IDs passed to the URL template. Two sub-steps were required:

**Step 1 — ID collection** (`02_collect_owa_ids.R`): The TBMM session list endpoint is queried for each legislative year and term, returning the document IDs for Plan and Budget Committee sessions. Results are stored in `data/metadata/owa_butce_ids.csv`.

**Step 2 — Download** (`03_scrape_owa.R`): Each ID is fetched from the OWA URL template with a 1-second delay. The response is a PDF delivered as an HTTP response body. Files are saved with a date-stamped filename derived from the session metadata.

---

## 4. PDF Text Extraction

### 4.1 Standard extraction

For most PDFs, text was extracted using `pdftools::pdf_text()`, an R wrapper around the libpoppler library. This function returns one character string per page, preserving the original whitespace layout. Pages are concatenated with a page-break marker before parsing.

Script: `04_extract_text_sbb.R` (SBB PDFs); OWA text is extracted within the same framework.

### 4.2 Special handling: 2018 budget season (16 PDFs)

Sixteen SBB PDFs from the 2018 budget season (October-November 2018) are in PDF version 1.6 format and are non-linearized. On Windows, `pdftools::pdf_text()` hangs indefinitely on these files. The root cause is a timeout in the underlying libpoppler Windows build when handling non-linearized PDF 1.6 structures.

**Solution:** Poppler's standalone command-line tool `pdftotext -layout` was used instead. This binary (available via MiKTeX on Windows) processed each file in approximately 10 seconds. The extracted text quality is equivalent to standard pdftools output; no encoding degradation was introduced.

Script: `05_extract_text_2018_poppler.R`

The extracted text files are stored as UTF-8 plain text in `data/raw/txt/`.

---

## 5. Speech Parsing Logic

### 5.1 Document structure

Each PBK transcript follows a consistent format:
- A header section (session date, attendees)
- Sequential speaker turns, each introduced by a speaker tag in capital letters
- Speaker tags take the form: `SPEAKER NAME (Province)`, `TITLE NAME`, or `CHAIR NAME`

### 5.2 Turn segmentation

The parser (`06_parse_speeches.R`) identifies speaker turns using a line-level regex pass:

1. Lines matching the speaker tag pattern are treated as turn boundaries
2. Text between consecutive boundaries is aggregated as a single speech
3. Each speech is assigned a sequence number (`oturum_sira`) within its PDF
4. Speeches shorter than 3 words (procedural utterances, "Teşekkür ederim" alone) are retained but flagged

### 5.3 Speaker name normalization

Raw speaker tags (`konusmaci_ham`) are parsed into normalized components:

| Raw format | Extracted fields |
|---|---|
| `MUHARREM IŞIK (Diyarbakır)` | `konusmaci_sade = "MUHARREM IŞIK"`, `sehir = "DİYARBAKIR"`, `rol = "milletvekili"` |
| `MALİYE BAKANI MEHMET ŞİMŞEK` | `konusmaci_sade = "MEHMET ŞİMŞEK"`, `rol = "bakan"` |
| `BAŞKAN MUHARREM IŞIK` | `konusmaci_sade = "MUHARREM IŞIK"`, `rol = "baskan"` |
| `MÜSTEŞAR ALİ BABACAN` | `konusmaci_sade = "ALİ BABACAN"`, `rol = "burokrat"` |

Turkish uppercase conversion is handled by a custom `turkish_upper()` function to avoid the standard `toupper()` locale issue (lowercase `i` converts to `I` instead of `İ` in Turkish).

### 5.4 Role assignment

Role priority (applied in order to avoid ambiguity):
1. **baskan** — tag contains "BAŞKAN" or "OTURUM BAŞKANI"
2. **bakan** — tag contains a ministry title ("X BAKANI", "BAKAN X")
3. **burokrat** — tag contains "MÜSTEŞAR", "GENEL MÜDÜR", "BAŞKAN YARDIMCISI", "BAŞKANI" (without committee-chair context)
4. **milletvekili** — tag contains a province name in parentheses and none of the above

### 5.5 Known parsing limitations

- **Institutional representatives** (Sayıştay, RTÜK, Rekabet Kurumu, etc.) occasionally appear with province-like parenthetical tags and are misclassified as `milletvekili`. Approximately 3,271 such rows remain in the corpus (2.5% of MP-role rows); they have `sicil = NA`. Correcting this would require named-entity recognition or a dedicated institutional representative lookup.
- **Province name whitelist** controls false positives from Roman numerals and other parenthetical content; 138 such false positives were identified and corrected during development.

---

## 6. Metadata Linkage

Metadata linkage was performed in four tiers, applied to distinct speaker roles.

### 6.1 MP matching (Tier 1)

The TBMM maintains a publicly accessible database of current and former MPs at:
`https://www5.tbmm.gov.tr/develop/owa/milletvekillerimiz_sd.mv_liste_eskilers?p_donem_kodu={XX}`

The scraper (`11_tbmm_mv_scrape.R`) collected all records for legislative terms 23-28 (June 2007 to present), yielding 3,329 records. Each record includes the MP's permanent registration number (`sicil`), which is stable across party changes and multiple terms.

Matching is performed on normalized names (`konusmaci_sade` after Turkish uppercasing) joined to the TBMM roster. A four-step match hierarchy is used:
1. Exact match on normalized name within the same term
2. Phonetic/fuzzy match for minor spelling variation
3. Manual alias resolution (Adil Kurt → Adil Zozani)
4. Manual CSV additions (`data/manuel/mv_metadata_manuel.csv`)

**Manual additions required:**
- **Ferit Mevlüt Aslanoğlu** — served in the 24th term (CHP, Istanbul) but TBMM's database omits this record (he died in office in 2014). Added via Wikipedia and news archive verification.
- **Kazım Kurt** — 24th-term record (CHP, Eskişehir, sicil 6713) exists in TBMM database but was missed by the scraper. Added via TBMM MP detail page.

**Alias resolution:**
- **Adil Kurt = Adil Zozani** — the MP legally changed his surname by court order. Old transcripts use the former name; the TBMM roster uses the new name. An alias table maps the old name to the correct `sicil`.

Final match rate: **98.0%** (MP role; chair 100%, minister 99.3%).

### 6.2 Committee chair matching (Tier 2)

PBK committee chairs are matched using a hand-curated lookup table stored in `R/pbk_baskan_yil.R`, mapping budget year to the canonical chair name. The matching script (`13_baskan_eslestir.R`) applies this lookup to all `baskan`-role rows.

Match rate: **100%** (all 68,561 chair-role speeches matched).

### 6.3 Minister matching (Tier 3)

Ministers are matched in two sub-tiers:

**MP-ministers** (Tier 3a): Ministers who were simultaneously serving as elected MPs are matched via the MP roster. This covers the majority of ministers in the corpus.

**Appointed technocrats** (Tier 3b): Non-MP ministers (technocrats appointed under Article 109 of the Constitution) are matched via a hand-curated CSV (`data/manuel/bakan_manuel.csv`, 18 individuals) with tenure dates. Examples include Mehmet Şimşek (Finance Minister 2009-2015, 2023+) and Naci Ağbal.

Match rate: **99.8%** (44 of 19,213 minister-role speeches unmatched; three edge cases: a minister identified only by first name, a bureaucrat misclassified as a minister, and Nimet Çubukçu who was actually an MP at the time).

### 6.4 Bureaucrat matching (Tier 4)

Senior bureaucrats (`burokrat` role) are not matched to a roster. Their appearances are retained in the corpus with speaker name but no sicil or party. This affects 383 speeches (0.2% of corpus).

---

## 7. Manual Corrections

All manual interventions are documented in version-controlled files under `data/manuel/` and in this methodology. The following corrections were applied:

| Intervention | Rows affected | File |
|---|---|---|
| Ferit Mevlüt Aslanoğlu 24th-term record | 5,374 | `mv_metadata_manuel.csv` |
| Kazım Kurt 24th-term record | 461 | `mv_metadata_manuel.csv` |
| Adil Kurt → Adil Zozani alias | 547 | inline in `12_mv_eslestirme.R` |
| Nimet Çubukçu removed from minister list | 0 (prevented misclassification) | `bakan_manuel.csv` |
| Berat Albayrak typo ("BERAK ALBAYRAK") | 103 | `bakan_typo_map.csv` |
| 18 appointed technocrat ministers | 2,745 | `bakan_manuel.csv` |
| Province name normalization (3 city names) | small | inline in `12_mv_eslestirme.R` |

---

## 8. Quality Control

### 8.1 Encoding fix (2016 PDFs)

Thirteen SBB PDFs from 2016 were generated with a defective glyph-encoding table that corrupted three Turkish characters. The corruption was systematic and consistent:

| Corrupted | Correct | Count |
|---|---|---|
| `Ģ` | `ş` | 92,465 |
| `ġ` | `Ş` | 10,812 |
| `Ġ` | `İ` | 15,319 |

The encoding diagnostic (`16_encoding_tani.R`) identified the pattern by comparing character frequency distributions across years. The fix (`17_encoding_duzelt.R`) applies character-level substitution to the affected text. Total characters corrected: 118,596.

### 8.2 Coverage verification

Three independent coverage tests were conducted (script: `18_kapsama_analizi.R`):

**Test 1 — Session-number sequencing:** Each PDF's text was scanned for "N'inci Toplantı" patterns to extract session sequence numbers. Year-by-year gaps were identified and cross-referenced against the TBMM 2023 PBK agenda list. All 13 "missing" session numbers correspond to non-budget PBK sessions (development plan hearings, legislation reviews, Central Bank presentations).

**Test 2 — Ministry detection:** All 19 ministries (with historical name variants) were searched across all PDFs. Zero PDFs went undetected; year-by-year gaps are consistent with ministry restructuring history.

**Test 3 — Volume sanity check:** Speeches per year were checked against expectations derived from the number of sessions and average speeches per session. No year showed anomalous volume.

### 8.3 Long-speech inspection

Speeches exceeding 5,000 words (an upper-tail outlier) were manually inspected. The longest speeches were committee chairs reading lengthy budget summaries — a real feature of the data, not a parser artifact. No concatenation errors were found.

---

## 9. Limitations

1. **~2.5% unmatched MP speeches.** After all matching tiers, 3,271 rows with `rol = "milletvekili"` remain unmatched (`sicil = NA`). These are primarily institutional representatives misclassified by the parser. They are retained in the corpus.

2. **Approximate ministry-speech linkage.** The `bakanlık` field (where present) is derived from detecting ministry names anywhere in the PDF, not from structured agenda items. A ministry name may appear as a cross-reference rather than indicating the day's primary topic. Precise linkage is left for future work.

3. **No inter-turn linkage.** The corpus records individual turns, not conversational threads. Reconstructing who is responding to whom requires the analyst to use session date and sequence number.

4. **Scope limited to committee stage.** Plenary (Genel Kurul) budget debates are not included. For plenary proceedings, see Demirtaş (2026).

5. **2009 budget year sparse.** Only 4 transcripts are available for budget year 2009 (TBMM OWA indexing issue). Treat count-based statistics for 2009 with caution.

---

## 10. Replication

All pipeline code is in `scripts/` (numbered in execution order) with helper functions in `R/`. The environment is managed with `renv`; run `renv::restore()` after cloning to install exact package versions.

For full step-by-step instructions, prerequisites, and expected outputs, see [`replication_guide.md`](replication_guide.md).

For a Turkish-language version of this methodology, see [`methodology_TR.md`](methodology_TR.md).
