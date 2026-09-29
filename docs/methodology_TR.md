# TBMM Plan ve Bütçe Komisyonu Bütçe Görüşmeleri Söylem Korpusu

**Sürüm:** v1.1.0 (28 Ağustos 2026); belge revizyonu 29 Eylül 2026
**Hazırlayan:** Emre Özyerden (eozyerden@gmail.com)
**Lisans:** Kod: MIT | Veri ve dokümantasyon: CC BY 4.0

---

## 1. Genel Bakış

Bu veri seti, **Türkiye Büyük Millet Meclisi (TBMM) Plan ve Bütçe Komisyonu (PBK)** bütçe görüşme tutanaklarının yapılandırılmış, makineyle okunabilir bir korpusunu içerir. Korpus, **17 yıllık dönemi (2009-2025 bütçe yılları)** kapsar ve **231.923 konuşma satırı** barındırır.

Türkiye'de PBK, merkezi yönetim bütçesinin parlamentoda görüşüldüğü ilk ve en detaylı kademedir. Bakanlık bütçeleri burada teker teker görüşülür; bakanlar, bürokratlar ve milletvekilleri uzun ve teknik tartışmalar yürütür. Bu görüşmeler genelde **Ekim-Kasım aylarında** yapılır ve bütçe kanunu Aralık ayında TBMM Genel Kurulu'na taşınır.

Bu korpusun amacı, Türkiye'nin maliye politikası söylemini niceliksel olarak analiz etmek isteyen araştırmacılara, başvuru kaynağı olabilecek temiz, metadata'lı bir veri seti sağlamaktır.

---

## 2. İçerik

### 2.1 Veri Dosyaları

| Dosya | İçerik | Format |
|---|---|---|
| `konusmalar_metadata.parquet` | Ana korpus, metadata'lı | Parquet |
| `mv_metadata.parquet` | TBMM 23-28. dönem milletvekili kayıtları | Parquet |
| `data/raw/pdf/sbb/` | SBB kaynaklı 196 ham PDF | PDF |
| `data/raw/pdf/owa/` | TBMM eski sistem kaynaklı 98 ham PDF | PDF |
| `data/raw/txt/` | Tüm PDF'lerin metin çıkarılmış halleri | UTF-8 TXT |

Ham PDF ve parquet dosyaları bu repoda **yer almaz**; Zenodo arşivinden indirilebilir.

### 2.2 Ana Korpus Sütunları (`konusmalar_metadata.parquet`)

| Sütun | Tip | Açıklama |
|---|---|---|
| `konusma_id` | string | Benzersiz konuşma kimliği |
| `dosya_kaynak` | string | Kaynak PDF dosya adı |
| `kaynak` | string | "SBB" veya "OWA" (TBMM eski sistem) |
| `tarih` | date | Konuşma tarihi |
| `butce_yili` | int | Görüşülen bütçenin yılı (görüşme yılı + 1, ay >= 10 ise) |
| `oturum_sira` | int | PDF içinde konuşma sırası |
| `konusmaci_ham` | string | Tutanakta geçen ham isim |
| `konusmaci_sade` | string | Normalize edilmiş isim |
| `sehir` | string | Konuşmacının ili (mv için) |
| `rol` | string | "milletvekili", "bakan", "baskan", "burokrat" |
| `parti_metinde` | string | Tutanakta belirtilen parti |
| `metin` | string | Konuşma metni |
| `kelime_sayisi` | int | Konuşmadaki kelime sayısı |
| `mv_sicil` | int | TBMM kalıcı milletvekili sicil numarası (varsa; milletvekili ve başkan satırlarında) |
| `mv_parti` | string | Eşleştirilmiş resmi parti (varsa) |
| `tbmm_donem` | int | TBMM dönem numarası (23-28) |
| `bakan_id` | string | Atanmış (mv olmayan) bakanlar için kimlik (yalnızca `rol = "bakan"`) |
| `bakanlik_adi` | string | Konuşan bakanın bakanlık adı |
| `bakanlik_baslangic`, `bakanlik_bitis` | date | Bakanlık görev başlangıç ve bitişi |
| `mv_sicil_bakan`, `mv_parti_bakan` | int, string | Aynı zamanda milletvekili olan bakanlar için sicil ve parti |
| `bakan_eslesme_tier` | string | Bakan eşleşme sonucu: `mv-bakan`, `atanmış`, `eslesemedi` |

Son yedi sütun v1.1.0'da eklenmiştir; tam sütun tanımları için bkz. [`data_dictionary.md`](data_dictionary.md).

### 2.3 Tanımlayıcı İstatistikler

| Metrik | Değer |
|---|---|
| Toplam konuşma | 231.923 |
| Toplam PDF (oturum tutanağı) | 294 |
| Kapsanan bütçe yılları | 2009-2025 (2015 takvim yılında görüşme yapılmadı; 2015 bütçe yılı kapsama dahildir) |
| Tarih aralığı | 17 Kasım 2008 – 29 Kasım 2024 |
| Tek başına milletvekili sayısı | 858 benzersiz milletvekili (TBMM sicil numarası ile tespit) |
| Bakan sayısı | 98 (80 milletvekili-bakan, 18 atanmış teknokrat) |
| PBK Başkanı sayısı | 6 kişi PBK'nin kendi seçilmiş başkanı olarak görev yaptı (bkz. `R/pbk_baskan_yil.R`); `rol = "baskan"` etiketli satırlarda ayrıca 13 TBMM Başkanı/Başkan Vekili de görünür (Genel Kurul başkanlık divanı üyeleri, PBK'nin kendi başkanı değil) — toplamda 19 benzersiz kişi |

**Rol dağılımı:**
- Milletvekili: %56.8
- Başkan: %33.3
- Bakan: %9.3
- Bürokrat: %0.6

**Metadata kapsama oranı:** %98,0 (milletvekili rolü; başkan %100, bakan %99,3)

---

## 3. Veri Toplama Yöntemi

### 3.1 Kaynaklar

İki resmi kaynaktan derleme yapılmıştır:

**Kaynak 1: SBB (Strateji ve Bütçe Başkanlığı, 2016-2025)**
- URL: `https://www.sbb.gov.tr/tbmm-plan-ve-butce-komisyonu-butce-tutanaklari/`
- 196 PDF dosyası
- Modern dönem, doğrudan PDF linkleri

**Kaynak 2: TBMM Eski Tutanak Sistemi (2009-2015)**
- URL şablonu: `https://www.tbmm.gov.tr/Tutanaklar/TutanakGoster/{ID}`
- 98 PDF dosyası
- TBMM eski sistem (kullanım dışı kalan altyapı)

### 3.2 Veri İşleme Hattı

```
1. SCRAPING (R + httr2 + rvest)
   ↓
2. PDF → METİN (pdftools + Poppler pdftotext)
   ↓
3. PARSE (R + stringr + regex)
   ↓
4. METADATA EŞLEŞTİRME (R)
   ↓
5. KALİTE KONTROL (encoding, eşleşme)
   ↓
6. YAPILANDIRILMIŞ KORPUS (parquet)
```

### 3.3 PDF Metin Çıkarma

Çoğu PDF için `pdftools::pdf_text()` (R paketi, libpoppler altyapısı) kullanılmıştır.

**İstisna:** 16 SBB PDF dosyası (2018 dönemi) PDF 1.6 sürümünde ve linearize edilmemiş yapıda olduğundan pdftools Windows'ta timeout sorunu yaratmıştır. Bu dosyalar için **Poppler komut satırı aracı (`pdftotext -layout`)** ile metin çıkarılmıştır. Script: `05_extract_text_2018_poppler.R`.

### 3.4 Milletvekili Metadata Toplama

TBMM'nin **eski milletvekili veritabanı sayfasından** dönem bazında milletvekili listesi çekilmiştir:

- URL şablonu: `https://www5.tbmm.gov.tr/develop/owa/milletvekillerimiz_sd.mv_liste_eskiler?p_donem_kodu={XX}`
- Çekilen dönemler: 23, 24, 25, 26, 27, 28
- Toplam: 3.329 mv kaydı
- Her mv için: ad-soyad, sicil numarası, parti, il, dönem

**Sicil numarası**, milletvekilinin TBMM sistemindeki kalıcı kimliğidir. Mv parti değiştirse veya birden çok dönem yapsa bile sicil değişmez.

---

## 4. Parse Mantığı ve Düzeltmeler

### 4.1 Konuşma Birimi Tanımı

Bir "konuşma" şöyle tanımlanmıştır: **Tek bir konuşmacının kesintisiz olarak verdiği söz.** Bir konuşmacının söz alıp bırakması ile sıradaki konuşmaya geçilir. Aynı oturumda aynı kişi defalarca konuşmuş olabilir; her seferinde ayrı konuşma satırı oluşur.

### 4.2 Konuşmacı Adı Normalizasyonu

Tutanaklarda isim formatları farklılık gösterir:
- "BAŞKAN MUHARREM IŞIK" (Komisyon Başkanı)
- "MUHARREM IŞIK (Diyarbakır)" (sıradan milletvekili)
- "MALİYE BAKANI MEHMET ŞİMŞEK"
- "MEHMET ŞİMŞEK (Maliye Bakanı)"

Parse aşamasında regex'lerle bu formatlar normalize edilmiştir:
- `konusmaci_ham`: Tutanaktaki orijinal yazım
- `konusmaci_sade`: Normalize edilmiş ad-soyad
- `rol`: Tutanaktaki sıfata göre atanan rol
- `parti_metinde`: Parantez içinde belirtilen parti (varsa)

### 4.3 Rol Atama Mantığı

| Rol | Tetikleyici |
|---|---|
| `baskan` | "BAŞKAN", "OTURUM BAŞKANI" gibi sıfatlar |
| `bakan` | "X BAKANI", "BAKAN X" formatı |
| `burokrat` | 24 ifadeden herhangi biri: "MÜSTEŞAR", "GENEL MÜDÜR", "SAYIŞTAY BAŞKANI", "RTÜK", "BDDK", "SPK", "REKABET KURUMU", "BAŞKAN YARDIMCISI", "DAİRE BAŞKANI" gibi (v1.1.0'da genişletildi; bkz. [`quality_note_v1.1.0.md`](quality_note_v1.1.0.md)) |
| `milletvekili` | İl bilgisi parantez içinde belirtilmiş satırlar (yukarıdakilerden değilse) |

### 4.4 Düzeltilmiş Parser Hataları (Yayın Öncesi)

| Hata | Etki | Çözüm |
|---|---|---|
| Başkan rolü mv'ye atanması | ~30.000 satır yanlış sınıflandırılmış | Regex sıralaması düzeltildi |
| Roma rakamı false positive (örn. "II nci") | 138 satır | İl listesi whitelist kontrolü eklendi |
| "TBMM BAŞKANI" mv olarak işaretlenme | 505 satır | Özel başkan kategorisi eklendi |
| Türkçe i → İ locale sorunu | Eşleşme oranını ~%5 düşürüyordu | `turkish_upper()` fonksiyonu yazıldı |

### 4.5 Encoding Düzeltmesi (2016 yılı)

2016 yılına ait 13 SBB PDF'inde bozuk bir yazı tipi/kodlama eşlemesi bulunur ve metin çıkarıldığında bazı Türkçe karakterler bozuk görünür:
- `Ģ` → `ş` (92.465 karakter)
- `ġ` → `Ş` (10.812 karakter)
- `Ġ` → `İ` (15.319 karakter)

Toplam 118.596 karakter düzeltilmiştir. v1.1.0'dan itibaren düzeltme (`R/parse_helpers.R` içindeki `fix_enc()`) konuşmacı segmentasyonundan önce, parser içinde uygulanır; v1.0.1'de segmentasyondan sonra uygulanıyordu ve bu, [`quality_note_v1.1.0.md`](quality_note_v1.1.0.md) belgesinde anlatılan 2016 segmentasyon hatasına yol açtı.

### 4.6 Şehir Adı Normalizasyonu

| Bulunan | Düzeltilen |
|---|---|
| HAKKÂRİ | HAKKARİ |
| ŞANLI URFA | ŞANLIURFA |
| KIRIKKKALE | KIRIKKALE |

### 4.7 Manuel Milletvekili Düzeltmeleri

TBMM'nin kendi veritabanında eksik olduğu tespit edilen milletvekilleri için manuel metadata eklenmiştir (`data/manuel/mv_metadata_manuel.csv`):

| MV | Düzeltme | Kaynak |
|---|---|---|
| Ferit Mevlüt Aslanoğlu | 24. dönem CHP İstanbul kaydı eklendi (TBMM eksik tutmuş, vekilken 2014'te vefat etti) | Wikipedia + haber arşivleri |
| Kazım Kurt | 24. dönem CHP Eskişehir sicil 6713 (TBMM kaydı var ama scraper kaçırmış) | TBMM mv detay sayfası |
| Adil Kurt = Adil Zozani | İsim alias tablosu (mahkeme kararıyla soyadı değişikliği) | Mahkeme kararı haberleri |
| Nimet Çubukçu | "atanmış bakan" listesinden çıkarıldı (aslında mv'ydi) | TBMM kaydı |
| Berat Albayrak | Parser typo'sundan kaynaklı "BERAK ALBAYRAK" düzeltmesi (1 satır; yayımlanmış v1.1.0 verisinden ölçüldü) | Manuel düzeltme |

### 4.8 Atanmış Bakan Listesi

Mv olmayan ama bakanlık yapmış teknokratlar için manuel CSV oluşturulmuştur (`data/manuel/bakan_manuel.csv`, 18 kişi):
- Mehmet Şimşek (2009-2015 ve 2023+ döneminde mv değildi)
- Naci Ağbal, Lütfi Elvan, Nureddin Nebati (2018 öncesi) ve diğerleri

---

## 5. Kapsama ve Sınırlılıklar

### 5.1 Kapsama Doğrulaması

**Üç bağımsız test yapılmıştır:**

1. **Toplantı numarası ardışıklığı:** Her PDF'in metnindeki "N'inci Toplantı" örüntüsü taranmış, yıl bazında ardışıklık kontrol edilmiştir.

2. **Bakanlık adı taraması:** Her PDF'in tam metninde 19 bakanlık adı (eski + yeni isimleri dahil) aranmış, yıl bazında kapsama matrisi oluşturulmuştur.

3. **TBMM resmi gündem listesi karşılaştırması:** 2023 PBK gündem listesi bizim envanterimizle karşılaştırılmıştır.

**Sonuç:** Bütçe görüşmeleri açısından korpus tamdır.

### 5.2 Kapsam Dışı Olanlar

| Kapsam Dışı | Sebep |
|---|---|
| 2008 ve öncesi bütçe görüşmeleri | TBMM/SBB sitelerinde mevcut değil |
| 2015 takvim yılında bütçe görüşmesi | Erken seçim sonucu görüşme yapılmadı |
| TBMM Genel Kurulu bütçe görüşmeleri | Bu korpus sadece komisyon aşamasıdır |
| PBK'nın bütçe-dışı toplantıları | Kalkınma planı, kanun teklifi vb. |

### 5.3 Bilinen Eksiklikler

Ayrıntılar için bkz. [`known_issues.md`](known_issues.md).

---

## 6. Olası Kullanım Alanları

- Maliye politikası söyleminin zaman içinde evrimi
- Bakan değişikliklerinin söylem üzerindeki etkisi
- İktidar-muhalefet retorik kontrastı
- Parti içi söylem heterojenliği
- Ekonomik kriz dönemlerinin parlamento söylemine yansıması
- Cinsiyete duyarlı bütçeleme söylemi (alt analiz)
- Maliye-para politikası söyleminin karşılaştırması

---

## 7. Replikasyon

Tüm adımlar R'da kodlanmıştır. Adım adım açıklamalar için bkz. [`replication_guide.md`](replication_guide.md).

**Bağımlılıklar:**
- R ≥ 4.5
- Paketler: `pdftools`, `rvest`, `httr2`, `arrow`, `dplyr`, `stringr`, `readr`, `here`, `renv`
- Poppler (`pdftotext.exe`): sadece 2018 dönemi 16 sorunlu PDF için

**Replikasyon adımları (yeni numaralandırmayla):**

1. `scripts/01_scrape_sbb.R` — SBB tutanaklarının indirilmesi
2. `scripts/02_collect_owa_ids.R` + `03_scrape_owa.R` — TBMM eski sistem tutanaklarının indirilmesi
3. `scripts/04_extract_text_sbb.R` — PDF'lerden ham metin çıkarma
4. `scripts/05_extract_text_2018_poppler.R` — 2018 sorunlu PDF'ler için Poppler
5. `scripts/06_parse_speeches.R` — Konuşma satırlarının parse edilmesi
6. `scripts/12_mv_eslestirme.R` — Milletvekili metadata eşleştirmesi
7. `scripts/13_baskan_eslestir.R` — Başkan eşleştirmesi
8. `scripts/14_bakan_eslestir.R` — Bakan eşleştirmesi

---

## 8. Sürüm Geçmişi

| Sürüm | Tarih | Notlar |
|---|---|---|
| v1.0 | Mayıs 2026 | İlk halka açık sürüm. 223.408 konuşma, %97.5 metadata kapsama. |
| v1.1.0 | 2026-08-28 | 231.923 konuşma, %98,0 (mv) — beş kusur düzeltildi (2016 segmentasyonu, 2013-2016 altbilgi sızıntısı, kurum temsilcisi rol sınıflandırması, 2015 başkan kimliği, yanlış raporlanan benzersiz milletvekili sayısı). Ayrıntı: [`quality_note_v1.1.0.md`](quality_note_v1.1.0.md). |

---

## 9. Atıf

```
Özyerden, E. (2026). TBMM Plan ve Bütçe Komisyonu Bütçe Görüşmeleri
Söylem Korpusu (2009-2025) [Veri seti]. Zenodo.
https://doi.org/10.5281/zenodo.20457565
```

Concept DOI (10.5281/zenodo.20457565) her zaman en güncel sürüme yönlendirir. Kullandığınız sürümü belirtmek için v1.1.0'ın sürüme özel DOI'sini kullanın: [10.5281/zenodo.22150634](https://doi.org/10.5281/zenodo.22150634).

---

## 10. İletişim

Emre Özyerden — eozyerden@gmail.com
