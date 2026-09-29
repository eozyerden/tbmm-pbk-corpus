# Quality Note: v1.1.0

**Context:** The TBMM Plan and Budget Committee Discourse Corpus was published as v1.0.1 on 30 May 2026 (concept DOI 10.5281/zenodo.20457565). During a research study using the corpus, five defects were found in the published version, two of them serious. All five have been corrected and republished as v1.1.0 on 28 August 2026 (commit `f89b3e3`, tagged `v1.1.0`). This note describes what they were, how they were found, what was fixed, and what remains.

None of the five was introduced by the corrections. All were present in the published version, and three had been there since the corpus was first built.

For the release summary see [CHANGELOG.md](../CHANGELOG.md); for the standing list of limitations see [known_issues.md](known_issues.md).

---

## 1. What was found

### 1.1 Speaker segmentation failure, budget year 2016

The most serious defect. Thirteen source PDFs of the 2016 hearings are affected. The text layer of these PDFs maps three Turkish characters to the wrong code points (a font encoding defect). How the PDFs render on screen was not checked. In the extracted text (Poppler, via `pdftools::pdf_text()`), `Ġ` appears in place of `İ`, `ġ` in place of `Ş`, and `Ģ` in place of `ş`. The corruption was known and documented: a repair pass replaced the corrupted characters and was recorded in the published `known_issues.md`.

What was not known is that the repair ran *after* speaker segmentation. The regex identifying speaker lines matches only standard Turkish uppercase characters, so headers reading `BAġKAN –` or `MALĠYE BAKANI ... –` were not recognised as speaker transitions. Those lines were absorbed into the preceding speaker's turn.

The consequences were severe and measurable:

| Measure | Published v1.0.1 | After correction |
|---|---|---|
| Recorded turns, budget year 2016 | 6,745 | 15,260 |
| Chair share of turns | 8.6% | 31.2% |
| Mean turn length (words) | 172.9 | 74.0 |

The corpus-wide chair share runs 25–48%; 2016 sat at 8.6%. One record attributed to a single MP was found on inspection to contain the chair's intervention and a minister's entire budget presentation. In the worst affected file, the correction raised the turn count by 259%.

The published corpus therefore contained, for that year, less than half of the turns it should have, with speaker attribution unusable.

### 1.2 Footer text leaking into speech records, budget years 2013–2016

A separate and wider problem. The parser strips page furniture — headers, footers, page numbers — using a set of fixed patterns. Two footer templates escaped it.

The first is an OWA-era template. TBMM's transcription unit was renamed at some point around 2012, from *Tutanak Müdürlüğü* to *Tutanak Hizmetleri Başkanlığı*. The cleaning rule matched only the older name. From calendar year 2012 onward, the three-line footer block was no longer recognised and its text entered the speech records.

The second is an SBB template used only in the 2016 files: a four-line block beginning with `T BM M` — the acronym broken by spurious inter-letter spaces, a separate PDF extraction artefact — followed by the unit name, the committee name, and a date/page line. One file carried a five-line variant with an added *İncelenmemiş Tutanaktır* ("uncorrected transcript") stamp.

Across the corpus this affected 5,268 turns, concentrated in budget years 2013, 2014, 2015 and 2016.

Two quantities here need to be kept apart, because conflating them produces a misleading figure. The turns containing footer text held roughly 15% of the corpus word volume — but most of those words are legitimate speech, not footer noise. The noise itself amounted to approximately 94,700 words, or about 0.54% of the corpus. Within the affected years it ran between 1.8% and 3.1% of those years' volume.

This one does not corrupt speaker attribution — those years' role distributions are normal. It adds noise to the text and inflates word counts, which matters for any analysis that uses word counts or length thresholds.

### 1.3 Metadata layer only partially executed

Discovered while re-running the pipeline after the fixes. The metadata stage comprises several scripts. Two of them — chair matching and minister matching — had not been run against the published dataset.

The published v1.0.1 therefore carried identity links for MPs only. No chair-role row carried an identifier (0 of 73,107), and ministers had no linked identifier. The chair lookup table (`R/pbk_baskan_yil.R`) also had no entry for budget year 2015; that gap has been filled. Running the two scripts added seven columns (`bakan_id`, `bakanlik_adi`, `bakanlik_baslangic`, `bakanlik_bitis`, `mv_sicil_bakan`, `mv_parti_bakan`, `bakan_eslesme_tier`) and populated `mv_sicil` for chair-role rows: in v1.1.0, 77,292 of 77,293 chair-role rows carry an identifier (the exception is a 2023 turn recorded as `BAŞKAN VEKİLİ` without a name).

To be clear about what the published "97.5% linkage" figure meant: it was correct, and `known_issues.md` §2.1 already specified that it applied to the MP role. But a user reading the headline figure could reasonably have assumed corpus-wide coverage. Figures are now reported by role (v1.1.0):

| Role | Rows | Linkage |
|---|---|---|
| MP | 131,755 | 98.0% |
| Chair | 77,293 | 100% (77,292 of 77,293) |
| Minister | 21,548 | 99.3% |
| Bureaucrat | 1,327 | out of scope |

### 1.4 Role misclassification of institutional representatives

Representatives of the Court of Accounts, the broadcasting and competition regulators, and similar bodies were being labelled as MPs. This was documented in v1.0.1 but its cause and scale were not known.

Two causes were found. The first is a regex defect. The patterns `MÜSTEŞAR\b` and `GENEL MÜDÜR\b` were intended to catch undersecretaries and directors-general. In Turkish these titles take possessive suffixes: `MÜSTEŞARI`, `GENEL MÜDÜRÜ`. The word-boundary assertion is ASCII-based, so in `MÜSTEŞARI` the suffix `I` counts as a word character and no boundary is found — the pattern never matches. `GENEL MÜDÜRÜ` matched only because its suffix begins with `Ü`, which the assertion treats as a non-word character. Two patterns of identical construction behaved differently by accident, and one of them failed silently from the day it was written.

The second cause is plain omission. Nine institutions and five official titles were absent from the pattern list altogether: RTÜK, BDDK, SPK, the Competition Authority, the Public Procurement Authority, the Ombudsman, TMSF, TÜİK and TÜBİTAK, and the titles *Başkan Yardımcısı*, *Daire Başkanı*, *Denetçi*, *Strateji Geliştirme* and *Teftiş Kurulu*. The pattern list now has 24 terms.

806 turns were reclassified. In the re-parsed corpus, bureaucrat turns rose from 521 to 1,327, or from 1.77 to 4.51 per source PDF — a far more plausible figure for hearings in which ministry officials field technical questions. MP linkage rose from 97.4% to 98.0%, since the reclassified turns had never been matchable against the MP roster in the first place.

Eleven turns remain misclassified: the committee's own deputy chairs, recorded as `PLAN VE BÜTÇE KOMİSYONU BAŞKAN VEKİLİ ...`. The chair patterns are anchored to the start of the speaker string. Removing the anchor was tested and rejected, because it would capture the deputy chairs of nine other institutions.

### 1.5 Unique MP count misreported

The README and methodology documents reported 1,184 unique MPs. The figure came from an early exploratory report that counted distinct raw speaker strings, before name normalisation and identifier matching. It was carried into the published documentation as if it counted people.

The correct figure is 858, counting distinct TBMM permanent identifiers among turns classified as MP speech.

The inflation had two sources. Sixty-two individuals appear under more than one spelling; in the worst case a single MP appears under eleven variants, adding ten spurious entries. A further 204 distinct speaker strings could not be matched to the roster at all and were counted as separate people.

The corrected figure is internally consistent. It yields 1,119 term-person pairs across five TBMM terms, implying roughly 260 individuals who spoke as MPs in more than one term — an ordinary re-election pattern. Per-term counts range from 93 to 339.

A related correction: the documentation reported 26 committee chairs. The actual figure is six people who served as chair of the Plan and Budget Committee, plus thirteen Speakers and Deputy Speakers of the Grand National Assembly who presided over sessions occasionally — nineteen individuals in total carrying the `baskan` role. The documentation now states both figures separately.

---

## 2. How these were found

Worth stating plainly, because it bears on how much confidence to place in the remainder.

None of the five was found by systematic quality control. All surfaced while chasing something else.

The sequence: during a research study using the corpus, a per-year distribution of turn lengths was requested while examining a length confound. Budget year 2016 was a visible outlier — 173 words mean against a corpus median of 8–9. Pursuing that produced the segmentation diagnosis. Pursuing the segmentation fix surfaced residual footer text, and pursuing that revealed the wider footer problem. Re-running the pipeline afterward revealed that the metadata stage had been incompletely executed. A reviewer then observed that 521 bureaucrat turns across 294 source PDFs was implausibly low, which produced the role-classification diagnosis. Verifying the published statistics before republishing produced the last one.

The 2016 defect was, in retrospect, trivially detectable. A single table of role distribution by year would have shown it: chair share at 8.6% against a range of 25–48% is not subtle. That table was never produced, because the verification run after the encoding repair asked "were the characters fixed?" and not "what else did the corruption break before we fixed it?"

The corrective conclusion is procedural, not about any individual step. A standing validation suite has been added (§4): per-year role distribution, turn counts, length distribution, embedded-header rate, linkage rate by role, all compared against the previous version. It runs after any pipeline change. This catches the class of defect that was missed, regardless of who or what runs the pipeline.

---

## 3. What was fixed and how it was verified

Four changes to the pipeline:

1. The footer-cleaning rule was extended to accept both names of the transcription unit.
2. A new rule was added for the SBB 2016 footer block, handling both the four-line and five-line variants. Strict patterns requiring exact consecutive matches were used rather than a flexible window, to avoid deleting legitimate text.
3. The encoding repair was moved into the parse pipeline, ahead of segmentation, where it belongs.
4. The role-classification patterns were corrected: boundary assertions removed, pattern list extended from 10 to 24 terms.

Eighty-four files were re-parsed for the first three fixes: all 34 files whose names begin with 2016, and the 50 OWA files from calendar years 2012–2014. The role correction was applied corpus-wide, recomputed from the existing speaker strings without re-parsing, since role assignment depends on nothing else.

Verification was specified in advance, with expected values stated before the run, and all criteria held:

| Criterion | Expectation | Result |
|---|---|---|
| 2016 turn count | 6,745 → ~15,260 | 15,260 |
| 2016 chair share | into 25–40% band | 31.2% |
| 2016 mean turn length | into 60–90 band | 74.0 |
| 2013/2014/2015 turn count | unchanged | unchanged |
| 2013/2014/2015 word count | down 1–2% | −1.77 / −1.79 / −1.83% |
| All other 13 years | no metric changes | max difference 0 |
| Corpus total | 223,408 → ~231,900 | 231,923 |
| Bureaucrat turns per source PDF | 1.77 → higher | 4.51 |
| Institutional representatives still labelled MP | 0 | 0 by the validation suite's patterns; 2 residual turns remain (see known_issues §2.5) |

The turn-count/word-count split matters: it confirms the fixes are independent and behaving as intended. Where only footer noise was present, turn boundaries were untouched and only word counts fell. Where segmentation was broken, turn counts rose.

Residual checks: corrupted characters, zero. Footer leakage, three instances remaining, all inspected and all legitimate speech — one MP discussing transcription procedure, two referring to the transcription service in substantive remarks. A legitimate-content test was run explicitly: in one file the phrase appears inside a genuine MP sentence about transcription practice, and the rule correctly left it alone because it did not match the block structure.

Before any of the role patterns were applied, each candidate was tested dry against the corpus and its linkage rate examined. A pattern capturing real MPs would show non-zero linkage; every one of the sixteen showed exactly zero, confirming none of them was catching parliamentarians. One pattern, *Başkan Yardımcısı*, was checked specifically against the risk of capturing the committee's own deputy chairs. It does not: the committee uses *Başkan Vekili*, a different word.

---

## 4. The validation suite

`scripts/99_validate.R` now runs after any pipeline change. It reports per-year structural metrics — turn counts, turns per source PDF, length distribution including the upper tail, role shares, linkage rates by role — and flags years falling outside expected bands. It runs residue checks for corrupted characters, footer text, embedded speaker headers and misclassified institutional representatives, identifies outlier source files, and compares everything against a stored baseline (`baseline_v1.1.0.csv`, included in the Zenodo data archive). For how to run it, see [replication_guide.md](replication_guide.md).

It was validated against the pre-correction data. It raises two band flags for budget year 2016 (chair share, mean length), three residue alerts (4,587 corrupted characters, 5,268 footer instances, 552 misclassified representatives), and lists seven of the affected source files as outliers. The signals are independent of one another, so the suite does not depend on any single indicator being sensitive.

Against the corrected corpus it raises one flag: budget year 2009, for low turn density per source PDF. That is the known and documented archive shortfall, not a defect.

---

## 5. What remains

**Known and unfixed.** Eleven turns by the committee's own deputy chairs are still labelled as MP speech, for the reason given in §1.4. A second parser limitation concerns embedded chair headers: 104 turns (0.045%; 88 in budget years 2009-2015) contain an embedded chair header. Of 106 such transitions, 93 have no space after the dash; 10 have a header line that starts without leading indentation; 2 have the header on the same line as the preceding speaker's text; and 1 has nothing after the dash on the header line. All four fall outside the speaker regex (`R/parse_helpers.R`), so the transition is missed and the chair's words are attached to the preceding turn. A few small linkage residuals are also listed in [known_issues.md](known_issues.md) §2.5. All of these are documented.

**Not fixable.** Budget year 2009 has four source PDFs against 13–21 for other years. The shortfall is in the source archive, not in processing. Time series should begin at 2010 with the truncation noted.

---

## 6. Implications for users

- **Per-turn rates confound role and topic.** Turn length varies systematically by role — chairs speak briefly and often, ministers at length — and the median turn is 8–9 words. Any per-turn rate therefore mixes who is speaking with what is being said. Measure per thousand words or at passage level.
- **Speaker-level analyses of budget year 2016 made with v1.0.1 should be redone.** Role, party, turn length, speaker identity and turn counts for that year were unreliable in v1.0.1 (§1.1).
- **Word counts for budget years 2013–2016 changed.** Footer text was removed (§1.2); word counts fell by 1.77–1.83% in 2013–2015 and by 3.11% in 2016.
- **Time series should begin at 2010.** Budget year 2009 is truncated in the source archive (§5).

---

## 7. Version and citation

The corrections are published as v1.1.0 with its own version DOI, [10.5281/zenodo.22150634](https://doi.org/10.5281/zenodo.22150634). v1.0.1 remains available and citable ([10.5281/zenodo.20457566](https://doi.org/10.5281/zenodo.20457566)), so anyone who used it retains a resolvable reference. The concept DOI [10.5281/zenodo.20457565](https://doi.org/10.5281/zenodo.20457565) always resolves to the latest version. The changelog states what changed and why; the known-issues document records each defect, its measured scale, and its resolution.

Papers using this corpus should report both v1.0.1 and v1.1.0 figures where the difference is material, and cite the specific version used.
