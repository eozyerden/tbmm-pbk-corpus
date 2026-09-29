# Data Dictionary

## `konusmalar_metadata.parquet` — Main corpus

| Column | Type | Description | Example | Notes |
|---|---|---|---|---|
| `konusma_id` | string | Unique speech ID | `"sbb_20181023_001_042"` | Format: `{source}_{date}_{session}_{sequence}` |
| `dosya_kaynak` | string | Source PDF filename | `"20181023_gorusme_sbb_001.pdf"` | |
| `kaynak` | string | Source archive | `"SBB"` or `"OWA"` | SBB = 2016-2025; OWA = 2009-2015 |
| `tarih` | date | Speech date | `2018-10-23` | ISO 8601; derived from filename |
| `butce_yili` | integer | Budget year under discussion | `2019` | If month >= 10: year + 1; else: year |
| `oturum_sira` | integer | Speech sequence within PDF | `42` | 1-indexed, restarts per PDF |
| `konusmaci_ham` | string | Speaker name as it appears in the transcript | `"MALİYE BAKANI MEHMET ŞİMŞEK"` | Raw, not normalized |
| `konusmaci_sade` | string | Normalized speaker name | `"MEHMET ŞİMŞEK"` | Title/role prefix stripped |
| `sehir` | string | Speaker's province (for MPs) | `"GAZİANTEP"` | Uppercase Turkish; NA for non-MPs |
| `rol` | string | Speaker role | `"milletvekili"` | One of: milletvekili, bakan, baskan, burokrat |
| `parti_metinde` | string | Party as stated in parentheses in the transcript | `"AKP"` | NA if not stated; not normalized |
| `metin` | string | Speech text | `"Teşekkür ederim..."` | UTF-8; encoding-corrected for 2016 |
| `kelime_sayisi` | integer | Word count of speech | `312` | Computed after normalization |
| `mv_sicil` | integer | Permanent TBMM registration number | `6228` | Populated for `rol = milletvekili` and `rol = baskan`. For ministers, identity is carried in `mv_sicil_bakan` or `bakan_id` instead. |
| `mv_parti` | string | Matched official party abbreviation | `"CHP"` | From TBMM roster; NA if unmatched |
| `tbmm_donem` | integer | TBMM legislative term | `24` | Range: 23-28 |
| `bakan_id` | string | Identifier for appointed (non-MP) technocrat ministers | `"atanan_012"` | Populated only for `rol = bakan` |
| `bakanlik_adi` | string | Ministry name for the minister speaking | `"MALİYE"` | Populated for all `rol = bakan` rows |
| `bakanlik_baslangic` | date | Start of the minister's term | `2018-07-09` | Appointed ministers only |
| `bakanlik_bitis` | date | End of the minister's term | `2021-04-21` | NA for ministers still in office at the end of the coverage period |
| `mv_sicil_bakan` | integer | TBMM permanent identifier for ministers who are also MPs | `6228` | |
| `mv_parti_bakan` | string | Party affiliation for ministers who are also MPs | `"AK Parti"` | |
| `bakan_eslesme_tier` | string | Minister matching outcome | `"mv-bakan"` | One of: `mv-bakan`, `atanmış`, `eslesemedi` |

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
| `milletvekili` | Member of Parliament (default for province-tagged speakers) |
| `bakan` | Minister (both MP-ministers and appointed technocrats) |
| `baskan` | Committee chair (Komisyon Başkanı) |
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
| `parti` | string | Party label as shown in the TBMM listing | `"CHP"` | At most 10 characters, so some labels are cut short (`YENİDEN RE`, `MEMLEKET P`). Differs between terms for 66 sicil values. TODO(Emre): state whether this is the party at election, at end of term or at scrape time |
| `kaynak_url` | string | TBMM page the record was scraped from | `"https://www5.tbmm.gov.tr/develop/owa/milletvekillerimiz_sd.mv_liste_eskiler?p_donem_kodu=23"` | One URL per term; `p_donem_kodu` is the term number |
| `cekim_tarihi` | date | Date the page was scraped | `2026-05-24` | Same value in every row |

### Coverage

- Terms 23-28 (June 2007 – present): 3,329 records from TBMM official database
- 2 additional manual records: Ferit Mevlüt Aslanoğlu (24th term, CHP Istanbul) and Kazım Kurt (24th term, CHP Eskişehir)
- 1 alias: Adil Kurt = Adil Zozani (court-ordered name change; alias resolved at match time, not stored as a separate record)

---

## `data/manuel/mv_metadata_manuel.csv` — Manual MP additions

Small CSV (< 10 rows) for MPs missing from TBMM's official roster. Same columns as `mv_metadata.parquet` plus a `not` (notes) column explaining the source.

## `data/manuel/bakan_manuel.csv` — Appointed ministers

Non-MP ministers (technocrats appointed by the Council of Ministers). Columns:

| Column | Type | Description |
|---|---|---|
| `isim_norm` | string | Normalized uppercase name |
| `gorev_baslangic` | date | Appointment date |
| `gorev_bitis` | date | End of tenure |
| `bakanlık` | string | Ministry name |
| `not` | string | Source note |
