# Known Issues and Limitations

## 1. Coverage Gaps

### 1.1 Pre-2009 proceedings not available
Budget hearings before the 2009 budget year (i.e., sessions held in late 2007 and late 2008) are not included. TBMM's legacy document system (OWA) does not have records for legislative year 1 and year 2 of the 23rd term. Coverage begins with the 2009 budget (sessions held November 2008 onward).

### 1.2 No budget deliberations in calendar year 2015
No PBK budget hearings took place in calendar year 2015. The 2015 budget year itself **is** included in the corpus (the 2015 budget was deliberated in late 2014). The June 2015 elections produced a hung parliament; snap elections were called for November 2015. The new government was formed on 24 November 2015, after the normal October-November budget window had passed. The 2016 budget was consequently deliberated in January-February 2016. `butce_yili = 2016` is correctly assigned to those sessions; there is no data gap — no hearings were held.

### 1.3 Incomplete 2009 budget data (4 sessions)
The 2009 budget year (sessions from late 2008) has only 4 transcripts in the TBMM OWA system, while all other years have 10-23. The reason is unknown (indexing issue or actual missing sessions). Treat 2009 with caution in count-based analyses.

### 1.4 No Plenary (Genel Kurul) proceedings
This corpus covers only the **committee stage** (Plan ve Bütçe Komisyonu). Plenary budget debates held in December each year are not included. For plenary proceedings, see Demirtaş (2026).

---

## 2. Metadata Limitations

### 2.1 ~2.5% of MP speeches unmatched (3,271 rows)
After manual corrections, 97.5% of MP-role rows have a matched TBMM registration number (`sicil`). The remaining ~2.5% are primarily:
- **Institutional representatives** (Sayıştay, RTÜK, Rekabet Kurumu, etc.) that the parser incorrectly classified as MPs. These appear with `rol = "milletvekili"` but are not elected members.
- A small number of genuine MPs whose names could not be normalized to match the TBMM roster.

Unmatched rows have `sicil = NA` and `parti = NA`. They are retained in the corpus.

### 2.2 Ferit Mevlüt Aslanoğlu — partial coverage
Aslanoğlu served as an MP in the 23rd term (CHP, Malatya) and the 24th term (CHP, Istanbul; died in office 2014). TBMM's own database omits his 24th-term record. His 24th-term appearances in the corpus (5,374 rows, budget years 2012-2015) are matched via a manually added record sourced from Wikipedia and news archives.

### 2.3 2012-2014 previously lower match rates
Before the manual corrections described above, match rates for budget years 2012 (70%), 2013 (73%), and 2014 (77%) were significantly below the corpus average. These are now resolved (96-99% range) through manual MP additions and the Adil Kurt → Adil Zozani alias.

---

## 3. Parser Limitations

### 3.1 Institutional representatives misclassified as MPs
The parser assigns `rol = "milletvekili"` to any speaker with a province tag in parentheses. Institutional representatives occasionally appear with province-like tags and are thus misclassified. The most prominent case is Erol Akbulut (Deputy Chair, Sayıştay), responsible for 82 rows. This is a known parser limitation; correcting it requires a separate NER/lookup sprint.

### 3.2 Ministry-speech mapping is approximate
The `bakanlık` (ministry) field, where present, is derived from detecting ministry names in the full PDF text, not from structured agenda items. A ministry name appearing in a PDF does not guarantee that the day's session was devoted to that ministry's budget. More precise mapping (via agenda headings + minister opening statement) is left for future work.

### 3.3 Speaker continuity not tracked
When the same speaker makes multiple interventions in a session, each is recorded as a separate row. The corpus does not link these into a single "floor time" unit, nor does it record the interlocutor. Cross-turn context must be reconstructed by the analyst using `tarih` + `oturum_sira`.

A related low-level case: where a speaker header is followed by a dash
with no intervening space (`ADI SOYADI (İl) -Metin`), the regex does not
match and the transition is missed. This occurs at background levels
throughout the corpus, most visibly in budget year 2025 (approximately
36 turns). Unlike the 2016 failure, it does not distort role
distribution or turn length at the population level.

---

## 4. Encoding Issues (Historical — 2016 PDFs)

Thirteen SBB PDFs from 2016 were generated with a defective encoding that corrupted three Turkish characters:
- `Ģ` should be `ş` (92,465 instances)
- `ġ` should be `Ş` (10,812 instances)
- `Ġ` should be `İ` (15,319 instances)

These have been corrected in the published corpus (total: 118,596 characters). The pre-correction version is preserved as `konusmalar_metadata_v1_pre_encoding.parquet` in the Zenodo archive for reproducibility.

### 4.1 Speaker segmentation failure in 2016 SBB transcripts

**Severity: high. Speaker-level data for budget year 2016 should not be
used.**

The character corruption documented in §4 (İ→Ġ, Ş→Ģ/ġ) was repaired at
the text level, but the repair was applied *after* speaker segmentation.
The speaker-line regex in `R/parse_helpers.R` matches only standard
Turkish uppercase characters; the corrupted glyphs Ġ, Ģ and ġ fall
outside that class. Speaker headers such as `BAĠKAN –` and
`MALĠYE BAKANI ... –` were therefore not recognised as speaker
transitions, and those lines were absorbed into the preceding speaker's
turn.

**Scale of the problem:**

| Measure | Value |
|---|---|
| Recorded turns for budget year 2016 | 6,745 |
| Turns containing an unrecognised speaker header | 2,691 (39.9%) |
| Total unrecognised speaker transitions | 4,529 |
| Estimated true turn count | ~11,274 |
| Share of 2016 word volume in affected turns | 71.7% |
| Affected source PDFs | 13 of 13 |

All thirteen affected PDFs are compromised throughout, not in isolated
passages. The recorded turn count for 2016 is roughly one third short of
what it should be, and the majority of the year's text sits inside
merged turns.

**Observable consequences:**

- Role distribution is severely distorted. MPs account for 86.2% of 2016
  turns against a corpus range of roughly 50-58%; the chair accounts for
  8.6% against a corpus range of 25-48%.
- Mean turn length is 173 words, the highest of any year; the corpus
  median is 8-9 words.
- Individual records conflate multiple speakers. One record attributed
  to a single MP was found to contain the chair's intervention and a
  minister's full budget presentation.

**Guidance for users:**

Budget year 2016 should be excluded from any analysis of speaker
attributes — role, party, turn length, speaker identity, turn counts,
or who-said-what. The text itself is present and the encoding is
correct; what is unreliable is the assignment of text to speakers and
the boundaries between turns. Analyses operating on the year's aggregate
text without reference to speakers are unaffected.

A corrected re-parse, applying the encoding repair before segmentation,
is planned. The corruption is confined to 2016: the glyphs Ġ, Ģ and ġ
appear in no other budget year.

---

## 5. Single Date Discrepancy

The PDF file `20211126_gorusme_sbb_001.pdf` contains the text "26 Ekim 2021" within its body, which conflicts with the filename date of 26 November 2021. This is a source document error (the PDF was generated with an incorrect internal date). The filename date (2021-11-26) is used in `tarih`. Content is unaffected.

---

## 6. 2018 PDF Special Handling

Sixteen SBB PDFs from the 2018 budget season (October-November 2018) are in PDF 1.6 format and non-linearized. `pdftools::pdf_text()` hangs indefinitely on these files under Windows. They were extracted using Poppler's `pdftotext -layout` command-line tool (script `05_extract_text_2018_poppler.R`). The extracted text quality is equivalent; no encoding issues were introduced.

---

## 7. Replication Dependency: Poppler

Reproducing the 2018 extraction step requires Poppler's `pdftotext` binary. On Windows, this is available via MiKTeX (`pdftotext.exe`). The path must be set in `05_extract_text_2018_poppler.R`. See `docs/replication_guide.md` for instructions.

---

## 8. Legacy TBMM Transcript Endpoint Behaviour

### 8.1 Legacy TBMM transcript endpoint behaviour

The 2009-2015 portion of the corpus was retrieved from the legacy TBMM
transcript endpoint (`TutanakGoster/{ID}`). Three properties of this endpoint
are undocumented and cost time to rediscover:

1. **Identifiers are not monotonic with date.** Within TBMM term 24, one
   legislative year occupies IDs 1062-1080 while another spans 20-1038.
   Sequential ID scanning is therefore not a valid strategy for discovering
   earlier sessions.
2. **HEAD requests return `text/html` regardless of actual content.** The
   real content type is only visible via GET. Any availability check built on
   HEAD responses will be unreliable.
3. **Unavailable IDs return a fixed-size PNG placeholder, not HTTP 404.**
   The response code is 200. Availability must be determined from response
   size and content type, not status code.

These were established by testing five IDs in June 2026. Whether the endpoint
serves pre-2009 committee transcripts remains undetermined: a low test ID
returned a genuine PDF, but its date was not verified.
