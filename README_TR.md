# TBMM Plan ve Bütçe Komisyonu Bütçe Görüşmeleri Söylem Korpusu

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.20457565.svg)](https://doi.org/10.5281/zenodo.20457565)
[![Lisans: MIT](https://img.shields.io/badge/Lisans%20(Kod)-MIT-yellow.svg)](LICENSE)
[![Lisans: CC BY 4.0](https://img.shields.io/badge/Lisans%20(Veri)-CC%20BY%204.0-lightgrey.svg)](LICENSE)
[![ORCID](https://img.shields.io/badge/ORCID-0000--0003--3577--4236-A6CE39?logo=orcid&logoColor=white)](https://orcid.org/0000-0003-3577-4236)

TBMM Plan ve Bütçe Komisyonu bütçe görüşmelerinin yapılandırılmış, makineyle okunabilir korpusu. **17 yıl (2009-2025)**, **231.923 konuşma satırı**, milletvekili-parti-il metadata'sı bağlantılı.

**English README:** [README.md](README.md)

---

## Kapsam

- 294 kaynak PDF (196 SBB + 98 TBMM eski sistem)
- 17 bütçe yılı (2009-2025). Not: Erken seçim takvimi nedeniyle 2015 takvim yılında PBK görüşmesi yapılmamıştır; ancak 2015 bütçe yılı korpusta yer alır (Kasım 2014'te görüşüldü).
- 858 benzersiz milletvekili (TBMM sicil numarası ile tespit) — parti, il, dönem metadata'lı
- 98 bakan — 80 milletvekili-bakan, 18 atanmış teknokrat
- 6 komisyon başkanı (ayrıca oturumlara zaman zaman başkanlık eden 13 TBMM Başkanı ve Başkanvekili)
- Rol bazında kimlik eşleşmesi: milletvekili %98,0, başkan %100, bakan %99,3 (bkz. [docs/data_dictionary.md](docs/data_dictionary.md))

> **Veri kalitesi.** 1.1.0 sürümü, v1.0.1'de bulunan beş hatayı
> düzeltiyor: 2016 bütçe yılında konuşmacı segmentasyonu, 2013-2016
> arasında altbilgi metni sızıntısı, kurumsal temsilcilerin rol
> sınıflandırması, 2015 için başkan kimliği ve yanlış raporlanmış
> benzersiz milletvekili sayısı (1.184 ham konuşmacı dizesi sayımıydı;
> doğru rakam 858). Bkz.
> [kalite notu](docs/quality_note_v1.1.0.md),
> [CHANGELOG.md](CHANGELOG.md) ve
> [docs/known_issues.md](docs/known_issues.md). v1.0.1 kullanıcıları
> güncellemelidir.

## Hızlı Başlangıç

```r
library(arrow)
library(dplyr)

df <- read_parquet("data/processed/konusmalar_metadata.parquet")

# Yıl bazında konuşma sayısı
df |> count(butce_yili)

# Parti bazında kelime sayısı (parti bilgisi "mv_parti" sütununda, "parti" değil)
df |>
  filter(!is.na(mv_parti)) |>
  group_by(mv_parti) |>
  summarise(toplam_kelime = sum(kelime_sayisi))
```

## Veri nerede?

İşlenmiş korpus ve ham kaynak PDF'ler Zenodo'da iki ayrı arşiv olarak yayımlanır (kayıt [22150634](https://zenodo.org/records/22150634)); bu repoda **yer almazlar**:

- **İşlenmiş veri** — `tbmm-pbk-corpus-data-v1.1.0.zip`: indirilen (sıkıştırılmış) boyut 76,0 MB; açıldığında ~86 MB. İçinde `konusmalar_metadata.parquet`, `mv_metadata.parquet`, `baseline_v1.1.0.csv`, veri sözlüğü ve lisans dosyası bulunur.
- **Ham kaynak PDF'ler** — `tbmm-pbk-corpus-raw-v1.1.0.zip`: indirilen (sıkıştırılmış) boyut 320,5 MB.

> **Zenodo arşivi:** [10.5281/zenodo.20457565](https://doi.org/10.5281/zenodo.20457565) (concept DOI, her zaman en güncel sürüme yönlendirir). Güncel sürüm: **v1.1.0** — sürüme özel DOI [10.5281/zenodo.22150634](https://doi.org/10.5281/zenodo.22150634).

Her iki zip de **düz** (flat) yapıda açılır; arşiv içinde `data/processed/` veya `data/raw/` alt klasörü yoktur. İndirip açtıktan sonra bu klasörleri (yoksa) oluşturup dosyaları içine taşıyın, böylece yollar bu README ve pipeline betikleriyle eşleşir. Her iki klasör de `.gitignore` içinde listelidir ve commit'lenmez.

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
- [`docs/quality_note_v1.1.0.md`](docs/quality_note_v1.1.0.md) — v1.1.0 kalite notu (İngilizce): düzeltilen beş hata, kimlik eşleştirmesi ve doğrulama paketi
- [`docs/coverage_report.md`](docs/coverage_report.md) — Kapsama doğrulama raporu

## Atıf

```
Özyerden, E. (2026). TBMM Plan and Budget Committee Discourse Corpus
[Veri seti]. Zenodo. https://doi.org/10.5281/zenodo.20457565
```

[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.20457565.svg)](https://doi.org/10.5281/zenodo.20457565)

Yukarıdaki atıf concept DOI'yi (10.5281/zenodo.20457565) kullanır; bu DOI her zaman en güncel sürüme yönlendirir. Analizinizde kullandığınız tam sürümü belirtmek isterseniz v1.1.0'ı doğrudan kaynak gösterin: DOI [10.5281/zenodo.22150634](https://doi.org/10.5281/zenodo.22150634).

Makine tarafından okunabilir atıf [`CITATION.cff`](CITATION.cff) dosyasında mevcuttur.

## Lisans

Kod (`scripts/`, `R/`): MIT  
Veri ve dokümantasyon: CC BY 4.0  
Bkz. [LICENSE](LICENSE)

## İletişim

Emre Özyerden ([ORCID: 0000-0003-3577-4236](https://orcid.org/0000-0003-3577-4236)) — eozyerden@gmail.com
