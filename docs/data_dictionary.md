# Data Dictionary

## `konusmalar_metadata.parquet` — Main corpus

231,923 rows (one row per speaker turn), 29 columns. Columns are listed in file order. Counts are measured from the published v1.1.0 data.

| Column | Type | Description | Example | Notes |
|---|---|---|---|---|
| `konusma_id` | string | Unique turn ID | `"owa_20081117_004"` | Format: `{kaynak}_{YYYYMMDD}_{oturum_sira}`, the sequence zero-padded to at least three digits. The date and sequence equal `tarih` and `oturum_sira` |
| `dosya_kaynak` | string | Source file name | `"20181023_gorusme_sbb_001.pdf"` | SBB rows give the PDF name; OWA rows give the name of the extracted text file (`"20081117_998_owa.txt"`) |
| `kaynak` | string | Source archive | `"sbb"` or `"owa"` | Lowercase. `sbb` = budget years 2016-2025; `owa` = 2009-2015 |
| `tarih` | date | Date of the sitting | `2018-10-23` | ISO 8601; derived from the file name. Range 2008-11-17 to 2024-11-29 |
| `butce_yili` | integer | Budget year under discussion | `2019` | If month >= 10: year + 1; else: year |
| `oturum_sira` | integer | Turn sequence within the source file | `42` | 1-indexed, restarts per file |
| `konusmaci_ham` | string | Speaker header as it appears in the transcript | `"MALİYE BAKANI MEHMET ŞİMŞEK"` | Raw, not normalized |
| `konusmaci_sade` | string | Speaker name with the title removed | `"Mehmet Şimşek"` | Title case; never NA |
| `sehir` | string | Text in parentheses after the speaker name | `"İzmir"` | As written, title case; normally the MP's province, and also present for ministers who are MPs. 118 distinct values, including non-province text such as `Devamla` ("continuing", 7,936 rows). NA when the header has no parenthesis |
| `rol` | string | Speaker role | `"milletvekili"` | One of: milletvekili, bakan, baskan, burokrat. Assigned by `classify_role()` in `R/parse_helpers.R` |
| `parti_metinde` | string | Party as stated in the speaker header | `NA` | NA in every row: the committee transcripts do not state party in the header. Party comes from the roster (`mv_parti`, `mv_parti_bakan`) |
| `metin` | string | Turn text | `"Teşekkür ederim..."` | UTF-8; encoding repaired for 2016 |
| `kelime_sayisi` | integer | Word count of the turn | `312` | Whitespace-separated tokens in `metin`. Range 1-8,961; median 8 |
| `is_baskanlik` | logical | Turn by the presiding officer | `TRUE` | Identical to `rol == "baskan"` (77,293 `TRUE`) |
| `is_kisa` | logical | Short turn | `TRUE` | `kelime_sayisi < 20` (160,789 `TRUE`, 69.3%) |
| `tbmm_donem` | integer | TBMM legislative term | `24` | Derived from `butce_yili` (`R/donem_haritasi.R`). Values 23, 24, 26, 27, 28; term 25 (June-November 2015) held no budget hearings |
| `sehir_kaynak` | string | Source of the province used for MP matching | `"corpus"` | `"corpus"` for MP rows whose `sehir` is a recognised province (125,881 rows). NA for other MP rows and for all other roles |
| `mv_sicil` | double | Permanent TBMM registration number | `6228` | Stored as double; every value is a whole number. Populated for matched `milletvekili` rows (129,170) and `baskan` rows (77,292). NA for ministers and bureaucrats; for ministers, identity is in `mv_sicil_bakan` or `bakan_id` |
| `mv_isim` | string | Name as listed on the TBMM roster for the matched `mv_sicil` | `"Harun ÖZTÜRK"` | Same rows as `mv_sicil` |
| `mv_parti` | string | Party label from the TBMM roster for the matched `mv_sicil` | `"CHP"` | Same rows as `mv_sicil`. Roster labels, at most 10 characters (e.g. `MEMLEKET P`); see `parti` in `mv_metadata.parquet` |
| `eslesme_tier` | integer | Matching tier for MPs and chairs | `1` | `0` chair lookup (`R/pbk_baskan_yil.R`); `1` name + province + term; `2` name + term; `3` fuzzy name (Levenshtein distance <= 1, province and term fixed). NA for unmatched MPs and for ministers and bureaucrats |
| `eslesme_durumu` | string | Matching outcome for MPs and chairs | `"matched"` | MP rows: `matched` (129,170), `unmatched` (2,585). Chair rows: `matched_baskan` (77,292), `unmatched_baskan` (1). NA for ministers and bureaucrats |
| `bakan_id` | string | Identifier for appointed (non-MP) technocrat ministers | `"atanan_012"` | Only rows with `bakan_eslesme_tier = "atanmış"` (2,858). `atanan_001`-`atanan_018` follow the row order of `data/manuel/bakan_manuel.csv` |
| `bakanlik_adi` | string | Ministry part of the minister's title, as written | `"MALİYE"` | Every `rol = bakan` row (21,548). Not normalized: 49 distinct values, including spelling variants |
| `bakanlik_baslangic` | date | Start of the minister's term | `2018-07-09` | Appointed ministers only (from `bakan_manuel.csv`) |
| `bakanlik_bitis` | date | End of the minister's term | `2021-04-21` | Appointed ministers only. NA where `bakan_manuel.csv` gives no end date (1,675 of 2,858 rows) |
| `mv_sicil_bakan` | integer | TBMM registration number for ministers who are also MPs | `7059` | Rows with `bakan_eslesme_tier = "mv-bakan"` (18,544) |
| `mv_parti_bakan` | string | Party label from the TBMM roster for ministers who are also MPs | `"AK Parti"` | Same rows as `mv_sicil_bakan` |
| `bakan_eslesme_tier` | string | Minister matching outcome | `"mv-bakan"` | For `rol = bakan`: `mv-bakan` (18,544), `atanmış` (2,858), `eslesemedi` (146). NA for other roles |

### Identity linkage rates by role

Linkage quality is measured differently per role — a single corpus-wide
percentage is not meaningful, since the identity field itself differs by role
(`mv_sicil` for MPs and chairs, `mv_sicil_bakan`/`bakan_id` for ministers).

| Role | Rows | Linkage rate |
|---|---|---|
| MP (`milletvekili`) | 131,755 | 98.0% |
| Chair (`baskan`) | 77,293 | 100%* |
| Minister (`bakan`) | 21,548 | 99.3% |
| Bureaucrat (`burokrat`) | 1,327 | not applicable |

Values are measured from the published v1.1.0 data (231,923 rows). MP and
chair linkage are the share of turns with a non-missing `mv_sicil`; minister
linkage is the share with `bakan_eslesme_tier` other than `eslesemedi`.

*77,292 of 77,293 chair-role turns; the exception is one 2023 turn recorded
as `BAŞKAN VEKİLİ` without a name. In v1.0.1 the chair columns were not
populated; see [quality_note_v1.1.0.md](quality_note_v1.1.0.md).

### Notes on `rol` values

| Value | Meaning |
|---|---|
| `milletvekili` | Member of Parliament (default: any speaker not matched by the bureaucrat, chair or minister patterns) |
| `bakan` | Minister (both MP-ministers and appointed technocrats) |
| `baskan` | Presiding officer: the committee chair, or occasionally a Speaker or Deputy Speaker of the Assembly (19 individuals: 6 committee chairs and 13 Speakers and Deputy Speakers) |
| `burokrat` | Senior bureaucrat (Müsteşar, Genel Müdür, etc.) |

### Notes on `butce_yili`

PBK budget hearings occur in October-November for the **following year's** budget.
- Speech dated 2018-10-23 → `butce_yili = 2019`
- Speech dated 2019-01-15 → `butce_yili = 2019` (rare; 2016 hearings ran Jan-Feb 2016)
- Exception: 2016 budget hearings were held January-February 2016 due to the 2015 electoral calendar disruption.

---

## `mv_metadata.parquet` — MP roster

Scraped by `scripts/11_tbmm_mv_scrape.R` from TBMM's MP-list pages (`mv_liste_eskiler`), one row per MP per term: 3,329 rows, 7 columns, no missing values (measured from the published v1.1.0 data). The records in `data/manuel/mv_metadata_manuel.csv` are not in this file; the matching script appends them at match time. Columns are listed in file order.

| Column | Type | Description | Example | Notes |
|---|---|---|---|---|
| `donem` | integer | TBMM legislative term of the listing | `23` | Range: 23-28; 535-592 rows per term |
| `sicil` | integer | Permanent TBMM registration number | `6228` | Unique within a term. 823 of the 1,937 distinct values appear in more than one term, always under the same name |
| `isim_ham` | string | Full name as listed by TBMM | `"Ferit Mevlüt ASLANOĞLU"` | Given names in mixed case, surname in capitals; not normalized |
| `il` | string | Province heading under which the MP is listed for that term | `"MALATYA"` | Uppercase Turkish; 81 distinct values. Differs between terms for 108 sicil values |
| `parti` | string | Party label as shown in the TBMM listing | `"CHP"` | Party as listed on the TBMM term roster on the scrape date (`cekim_tarihi`); may not reflect party changes during the term. At most 10 characters, so some labels are cut short (`YENİDEN RE`, `MEMLEKET P`). Differs between terms for 66 sicil values |
| `kaynak_url` | string | TBMM page the record was scraped from | `"https://www5.tbmm.gov.tr/develop/owa/milletvekillerimiz_sd.mv_liste_eskiler?p_donem_kodu=23"` | One URL per term; `p_donem_kodu` is the term number |
| `cekim_tarihi` | date | Date the page was scraped | `2026-05-24` | 2026-05-24 in every row: all terms were scraped on that date |

### Coverage

- Terms 23-28, as listed on 2026-05-24: 3,329 records from TBMM official database
- 2 additional manual records: Ferit Mevlüt Aslanoğlu (24th term, CHP Istanbul) and Kazım Kurt (24th term, CHP Eskişehir)
- 1 alias: Adil Kurt = Adil Zozani (court-ordered name change; alias resolved at match time, not stored as a separate record)

---

## `data/manuel/mv_metadata_manuel.csv` — Manual MP additions

MPs missing from TBMM's official roster: 2 rows (Ferit Mevlüt Aslanoğlu and Kazım Kurt, 24th term). The columns are those of `mv_metadata.parquet`, with `parti` before `il`; there is no notes column.

| Column | Type | Description |
|---|---|---|
| `donem` | integer | TBMM legislative term |
| `sicil` | integer | Permanent TBMM registration number |
| `isim_ham` | string | Full name, in the roster's format |
| `parti` | string | Party label |
| `il` | string | Province (uppercase Turkish) |
| `kaynak_url` | string | `manuel` in both rows |
| `cekim_tarihi` | date | Date the record was added (`2026-05-27`) |

## `data/manuel/bakan_manuel.csv` — Appointed ministers

Non-MP ministers (technocrats appointed by the Council of Ministers): 18 rows. Columns:

| Column | Type | Description |
|---|---|---|
| `isim_kanonik` | string | Canonical name in uppercase Turkish, matched against the minister's name in the speaker header |
| `bakanlik` | string | Ministry name (e.g. `Sağlık`) |
| `baslangic_tarihi` | date | Appointment date |
| `bitis_tarihi` | date | End of tenure; `NA` for ministers still in office when the list was compiled |
| `parti` | string | `Bağımsız/Teknokrat` in every row |
| `not` | string | Source note |
