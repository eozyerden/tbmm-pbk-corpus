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
| `sicil` | integer | Permanent TBMM MP registration number | `6228` | NA for non-MPs and unmatched |
| `parti` | string | Matched official party abbreviation | `"CHP"` | From TBMM roster; NA if unmatched |
| `tbmm_donem` | integer | TBMM legislative term | `24` | Range: 23-28 |

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

| Column | Type | Description | Example | Notes |
|---|---|---|---|---|
| `sicil` | integer | Permanent TBMM registration number | `6228` | Stable across terms and party changes |
| `isim_ham` | string | Full name as in TBMM database | `"Ferit Mevlüt ASLANOĞLU"` | Mixed case |
| `isim_norm` | string | Normalized uppercase name | `"FERİT MEVLÜT ASLANOĞLU"` | Used for matching |
| `parti` | string | Party abbreviation | `"CHP"` | As of the listed term |
| `il` | string | Province | `"MALATYA"` | Uppercase Turkish |
| `donem` | integer | TBMM legislative term | `23` | Range: 23-28 |
| `kaynak` | string | Record source | `"tbmm"` or `"manuel"` | manuel = added via `mv_metadata_manuel.csv` |

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
