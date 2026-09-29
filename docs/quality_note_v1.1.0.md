<!--
DRAFT FOR AUTHOR REVIEW. Not final text.
Assembled only from: the Zenodo v1.1.0 release notes (API record 22150634),
CHANGELOG.md, docs/known_issues.md, docs/coverage_report.md, the git log and
git diff between the v1.0.1 and v1.1.0 tags, and commit messages. Anything not
stated in those sources is left as a TODO(Emre) comment rather than inferred.
NOTE: the instruction for the closing "Recommended practice" section arrived
truncated. That section is provisional: it paraphrases only what the Zenodo
v1.1.0 notes say about turn length and role. Confirm its intended scope.
Search for "TODO(Emre)" to find every open point.
-->

# Quality note: v1.1.0

Version 1.1.0 corrects five defects present in v1.0.1. Users of v1.0.1 should
migrate, particularly for any speaker-level analysis. The corpus total rises
from 223,408 to 231,923 turns. The fixes were made in commit `f89b3e3`, which
is the commit tagged `v1.1.0`. This note describes each defect, how far it
reached, and what changed. For the release summary see
[CHANGELOG.md](../CHANGELOG.md); for the standing list of limitations see
[known_issues.md](known_issues.md).

| # | Defect | Budget years | Headline measure |
|---|---|---|---|
| 1 | Speaker segmentation failure | 2016 | 6,745 turns recorded; 15,260 after the fix |
| 2 | Page-footer text in speech records | 2013-2016 | 5,268 turns affected |
| 3 | Role misclassification of institutional representatives | not stated in sources | 806 turns moved from MP to bureaucrat |
| 4 | Committee chair unidentified | 2015 | chair linkage 0.5% to 100% |
| 5 | Unique MP count misreported | corpus-wide figure | 1,184 reported; correct figure 858 |

---

## 1. Speaker segmentation failure, budget year 2016

### What was wrong

Speaker headers in the 2016 transcripts were not recognised as speaker
transitions, so turns were merged across speakers. Headers such as `BAĠKAN –`
and `MALĠYE BAKANI ... –` were absorbed into the preceding speaker's turn.

### Scope

- Budget year 2016; all 13 of 13 affected source PDFs (SBB).
- Recorded turns for 2016: 6,745. Turns containing an unrecognised speaker
  header: 2,691 (39.9%). Total unrecognised speaker transitions: 4,529.
- Share of the year's word volume in affected turns: 71.7%.
- Role distribution was distorted: MPs 86.2% of 2016 turns against a corpus
  range of roughly 50-58%; the chair 8.6% against a corpus range of 25-48%.
- Mean turn length was 173 words, the highest of any year; the corpus median
  is 8-9 words.
- One record attributed to a single MP was found to contain the chair's
  intervention and a minister's full budget presentation.
- After the fix: 15,260 turns for 2016 (against 6,745), chair share 31.2%
  (against 8.6%), mean turn length 74.0 words (against 172.9).

<!-- TODO(Emre): known_issues.md §4.1 gives an "estimated true turn count" of
about 11,274 (6,745 recorded plus 4,529 unrecognised transitions), but the
corrected parse yields 15,260. The sources do not explain the gap. Decide
whether to comment on it, or drop the estimate from this note. -->

### Cause

The character corruption documented in known_issues.md §4 (İ as Ġ, Ş as Ģ or
ġ) had been repaired at the text level, but the repair was applied after
speaker segmentation. The speaker-line regex in `R/parse_helpers.R` matches
only standard Turkish uppercase characters, so the corrupted glyphs Ġ, Ģ and
ġ fell outside it. The corruption is confined to 2016: those glyphs appear in
no other budget year. It affected thirteen SBB PDFs from 2016 (118,596
characters in total).

<!-- TODO(Emre): known_issues.md §4 says the PDFs "were generated with a
defective encoding", while the code comment added to R/parse_helpers.R in
f89b3e3 says the corruption arose at the PDF-to-text extraction stage through a
faulty font/encoding mapping. State which is correct. -->

### How it was detected

<!-- TODO(Emre): not recorded in the sources. The commit messages for 14e1723
and 0c38a8c describe the defect and measure its scale, but not how it was
first noticed. -->

### Fix

Commit `f89b3e3`. The encoding repair (`fix_enc()` in `R/parse_helpers.R`) now
runs on the raw text lines in `scripts/06_parse_speeches.R`, before footer
cleaning and speaker segmentation. All 34 source files with 2016 in their name
were re-parsed. The defect had earlier been documented in commits `14e1723` and
`0c38a8c` (2026-08-26).

### Implications for downstream analysis

For v1.0.1, known_issues.md advised excluding budget year 2016 from any
analysis of speaker attributes (role, party, turn length, speaker identity,
turn counts, who-said-what). The text and its encoding were correct; what was
unreliable was the assignment of text to speakers and the boundaries between
turns. Analyses of the year's aggregate text without reference to speakers
were unaffected. In v1.1.0 the year is re-segmented; users of v1.0.1 should
migrate for any speaker-level analysis of that year.

---

## 2. Footer text in speech records, budget years 2013-2016

### What was wrong

Two page-footer templates escaped the text-cleaning rules, and their content
entered the speech records.

### Scope

- 5,268 turns across budget years 2013, 2014, 2015 and 2016.
- Speaker attribution was not affected. Only the text of those turns carried
  extra content, and word counts were correspondingly inflated.
- After the fix, word counts fell by 1.77-1.83% in budget years 2013-2015 and
  by 3.11% in 2016.
- Three instances of the phrase remain in the corpus, all verified as
  legitimate speech about the transcription service.

### Cause

- First template (OWA era): TBMM's transcription unit was renamed from
  *Tutanak Müdürlüğü* to *Tutanak Hizmetleri Başkanlığı* around calendar year
  2012. The cleaning rule matched only the older name, so the three-line
  footer block was no longer recognised from that point.
- Second template (2016 SBB files only): a four-line block beginning with
  `T BM M`, the acronym broken by spurious inter-letter spacing from PDF
  extraction, followed by the unit name, the committee name and a date/page
  line. One file (`20160128_gorusme_sbb_001.pdf`) carries a five-line variant
  with an added *İncelenmemiş Tutanaktır* stamp.

### How it was detected

<!-- TODO(Emre): not recorded in the sources. -->

### Fix

Commit `f89b3e3`, in `clean_pdf_text()` in `R/parse_helpers.R`. The OWA rule
now accepts both names of the transcription unit; a new rule handles both
variants of the SBB template.

### Implications for downstream analysis

Speaker-level variables were not affected. Text-based measures for these four
budget years, in particular word counts, differed in v1.0.1 by the percentages
given under Scope.

---

## 3. Role misclassification of institutional representatives

### What was wrong

Institutional representatives (bureaucrats) were classified as MPs. The parser
assigns `rol = "milletvekili"` to any speaker with a province tag in
parentheses, and representatives of institutions occasionally appear with
province-like tags.

### Scope

- 806 turns moved from `milletvekili` to `burokrat`.

<!-- TODO(Emre): the sources do not say which budget years these 806 turns fall
in. Add the per-year breakdown if you want it in the note. -->

- The bureaucrat count rose from 521 to 1,327, or from 1.77 to 4.51 turns per
  session day.
- MP linkage rose from 97.4% to 98.0%, because the reclassified turns were
  never matchable against the MP roster.
- Remaining: eleven turns by the committee's own deputy chairs (recorded as
  `PLAN VE BÜTÇE KOMİSYONU BAŞKAN VEKİLİ ...`) are still labelled
  `milletvekili`. The chair patterns are anchored to the start of the speaker
  string and do not match; removing the anchor was tested and rejected because
  it would capture the deputy chairs of nine other institutions.

### Cause

Two causes were identified.

1. The patterns `MÜSTEŞAR\b` and `GENEL MÜDÜR\b` failed against Turkish
   possessive suffixes. In `MÜSTEŞARI` the suffix begins with ASCII `I`, which
   the word-boundary assertion treats as a word character, so no boundary is
   found. `GENEL MÜDÜRÜ` matched only because its suffix begins with `Ü`,
   which is not an ASCII word character.
2. Several institutions were absent from the pattern list: RTÜK, BDDK, SPK,
   the Competition Authority, the Public Procurement Authority, the Ombudsman,
   TMSF, TÜİK and TÜBİTAK, along with the titles *Başkan Yardımcısı*, *Daire
   Başkanı*, *Denetçi*, *Strateji Geliştirme* and *Teftiş Kurulu*. (The
   release notes count these as fourteen institutions.)

### How it was detected

<!-- TODO(Emre): not recorded in the sources. -->

### Fix

Commit `f89b3e3`, in `classify_role()` in `R/parse_helpers.R`. The boundary
assertions were removed and the institution list extended. known_issues.md
states the list now has 23 terms.

<!-- TODO(Emre): the diff of classify_role() shows 10 existing terms plus 14
added, which is 24, not 23. Check the count before publishing. -->

### Implications for downstream analysis

In v1.0.1 these 806 turns were counted as MP speech, so MP-role turn counts
and bureaucrat-role turn counts differ between the two versions.

<!-- TODO(Emre): the sources state no further guidance for role-based analysis
(for example, whether v1.0.1 MP-versus-bureaucrat comparisons should be
redone). Add if intended. -->

---

## 4. Committee chair for budget year 2015

### What was wrong

The committee chair for budget year 2015 was unidentified. Chair linkage for
that year was 0.5%.

### Scope

- Budget year 2015 (deliberated in late 2014).
- Chair linkage for that year rises from 0.5% to 100%.

### Cause

The chair lookup table `R/pbk_baskan_yil.R` had no entry for 2015 (the value
was `NA`, annotated as not verifiable). The gap is now filled.

### How it was detected

<!-- TODO(Emre): not recorded in the sources. -->

### Fix

Commit `f89b3e3`. The 2015 entry in `R/pbk_baskan_yil.R` is now Recai Berber
(Manisa), with the source recorded in the code comment as the page header of
the transcripts (17 of 17 files, 2014-10-23 to 2014-11-25) and the press
archive.

<!-- TODO(Emre): confirm you want the name stated in this note. -->

### Implications for downstream analysis

<!-- TODO(Emre): not stated in the sources beyond the linkage figure above. -->

---

## 5. Unique MP count misreported

### What was wrong

Versions up to v1.0.1 reported 1,184 unique MPs. The figure was carried into
the README and methodology documents as if it were a count of people. The
correct figure is 858.

### Scope

A documentation figure; the speech records themselves are not described as
affected in the sources. The corrected figure counts distinct TBMM permanent
identifiers among turns classified as MP speech.

### Cause

1,184 was a count of distinct raw speaker strings taken from an early
exploratory report, before name normalisation and identifier matching. The
inflation had two sources: sixty-two individuals appear under more than one
spelling of their name (in the most extreme case one MP under eleven variants,
adding ten spurious entries), and a further 204 distinct speaker strings could
not be matched to the MP roster at all and were counted as separate people.

The corrected figure is internally consistent: it yields 1,119 term-person
pairs across the five TBMM terms in the corpus, implying that roughly 260
individuals spoke as MPs in more than one term. Per-term counts range from 93
to 339.

### How it was detected

<!-- TODO(Emre): not recorded in the sources. -->

### Fix

Commit `f89b3e3` corrected the figure in the documentation. Commit `8601d14`
(on `main`, after the `v1.1.0` tag) corrected the README notices, which still
said four defects instead of five.

### Implications for downstream analysis

<!-- TODO(Emre): not stated in the sources. -->

---

## Chair and minister identity matching

Chair and minister identity matching, which had not been run against the
published dataset, is included from v1.1.0. It adds seven columns:
`bakan_id`, `bakanlik_adi`, `bakanlik_baslangic`, `bakanlik_bitis`,
`mv_sicil_bakan`, `mv_parti_bakan` and `bakan_eslesme_tier`. Column
definitions are in [data_dictionary.md](data_dictionary.md).

Identity linkage is now reported by role: MP 98.0%, chair 100%, minister
99.3%. The previously headlined 97.5% applied to the MP role only. The release
notes give 98 ministers (80 MP-ministers and 18 appointed technocrats) and 6
committee chairs, plus 13 Speakers and Deputy Speakers of the Assembly who
presided occasionally.

<!-- TODO(Emre): the data_dictionary.md diff between v1.0.1 and v1.1.0 also
renames `sicil` to `mv_sicil` and `parti` to `mv_parti`. CHANGELOG.md lists
only the seven added columns. Decide whether the renames belong in this note
or in the changelog. -->

---

## Validation suite

From v1.1.0 the repository includes `scripts/99_validate.R`, a standing
validation suite run after any pipeline change. It reports per-year structural
metrics (turn counts, turns per source PDF, length distribution including the
upper tail, role shares, linkage rates), flags years falling outside expected
bands, runs residue checks for corrupted characters, footer text, embedded
speaker headers and misclassified institutional representatives, and compares
against a stored baseline (`data/processed/baseline_v1.1.0.csv`, reference
metrics).

The suite was validated against the pre-correction data: it raises two band
flags and three residue alerts for budget year 2016, and lists seven of the
affected source files as outliers.

The defects corrected in v1.1.0 were not found by systematic quality control.
They surfaced while investigating an unrelated measurement question. The suite
exists so that the same class of defect is caught by design rather than by
chance.

<!-- TODO(Emre): how to run the suite is documented only in a comment at the
foot of scripts/99_validate.R; neither README nor replication_guide.md
mentions it. Add a run instruction here if wanted. Also state where
baseline_v1.1.0.csv is meant to be obtained, since data/processed/ is not
tracked in git. -->

---

## Recommended practice

<!-- TODO(Emre): PROVISIONAL. The instruction for this section was cut off; it
is limited to what the Zenodo v1.1.0 release notes say about turn length and
role. Confirm or extend. -->

Turn lengths vary by two orders of magnitude and systematically by role: the
median turn is 8-9 words, chairs speak briefly and often, and ministers speak
at length. Per-turn rates therefore confound topic with role. Measures
normalised by word volume, or computed at passage level, are recommended.
