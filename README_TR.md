# TBMM Plan ve Bütçe Komisyonu Bütçe Görüşmeleri Söylem Korpusu (2009-2025)

[![DOI](https://zenodo.org/badge/DOI/PENDING.svg)](https://doi.org/PENDING)
[![Lisans: MIT](https://img.shields.io/badge/Lisans%20(Kod)-MIT-yellow.svg)](LICENSE)
[![Lisans: CC BY 4.0](https://img.shields.io/badge/Lisans%20(Veri)-CC%20BY%204.0-lightgrey.svg)](LICENSE)
[![ORCID](https://img.shields.io/badge/ORCID-0000--0003--3577--4236-A6CE39?logo=orcid&logoColor=white)](https://orcid.org/0000-0003-3577-4236)

TBMM Plan ve Bütçe Komisyonu bütçe görüşmelerinin yapılandırılmış, makineyle okunabilir korpusu. **17 yıl (2009-2025)**, **223.408 konuşma satırı**, milletvekili-parti-il metadata'sı bağlantılı.

**English README:** [README.md](README.md)

---

## Kapsam

- 294 PDF oturum tutanağı (196 SBB + 98 TBMM eski sistem)
- 17 bütçe yılı (2009-2025). Not: Erken seçim takvimi nedeniyle 2015 takvim yılında PBK görüşmesi yapılmamıştır; ancak 2015 bütçe yılı korpusta yer alır (Kasım 2014'te görüşüldü).
- 1.184 benzersiz milletvekili — parti, il, dönem metadata'lı
- ~100 bakan (mv-bakan + atanmış teknokrat)
- %97.5 metadata eşleşme oranı

## Hızlı Başlangıç

```r
library(arrow)
library(dplyr)

df <- read_parquet("data/processed/konusmalar_metadata.parquet")

# Yıl bazında konuşma sayısı
df |> count(butce_yili)

# Parti bazında kelime sayısı
df |>
  filter(!is.na(parti)) |>
  group_by(parti) |>
  summarise(toplam_kelime = sum(kelime_sayisi))
```

## Veri nerede?

Ham PDF'ler (~670 MB) ve işlenmiş Parquet dosyaları (~160 MB) bu repoda **yer almaz** — Zenodo arşivinden indirilebilir: [DOI beklemede].

Bu GitHub reposu şunları içerir:
- Tüm pipeline kodu (scraping, parse, metadata eşleştirme)
- Manuel düzeltmeler (küçük CSV'ler)
- Dokümantasyon (metodoloji, veri sözlüğü, bilinen sorunlar)

## Dokümantasyon

- [`docs/methodology_TR.md`](docs/methodology_TR.md) — Detaylı Türkçe metodoloji
- [`docs/methodology.md`](docs/methodology.md) — English methodology
- [`docs/data_dictionary.md`](docs/data_dictionary.md) — Sütun açıklamaları
- [`docs/replication_guide.md`](docs/replication_guide.md) — Adım adım replikasyon
- [`docs/known_issues.md`](docs/known_issues.md) — Bilinen sınırlılıklar
- [`docs/coverage_report.md`](docs/coverage_report.md) — Kapsama doğrulama raporu

## Atıf

```
Özyerden, E. (2026). TBMM Plan ve Bütçe Komisyonu Bütçe Görüşmeleri
Söylem Korpusu (2009-2025) [Veri seti]. [![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.20457565.svg)](https://doi.org/10.5281/zenodo.20457565)
```

## Lisans

Kod (`scripts/`, `R/`): MIT  
Veri ve dokümantasyon: CC BY 4.0  
Bkz. [LICENSE](LICENSE)

## İletişim

Emre Özyerden ([ORCID: 0000-0003-3577-4236](https://orcid.org/0000-0003-3577-4236)) — eozyerden@gmail.com
