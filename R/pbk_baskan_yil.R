# R/pbk_baskan_yil.R
# TBMM Plan ve Bütçe Komisyonu başkanı: butce_yili → kanonik isim lookup
#
# Kaynak doğrulama:
#   23. dönem (2007-2011) — Sait Açba: Wikipedia + kullanıcı notu
#   24. dönem (2011-2015) — Lütfi Elvan: AA.com.tr haberi (24 Şubat 2019'dan önce "ilk başkanlık": 2011-Aralık 2013)
#     2015: doğrulanamadı (Elvan Aralık 2013'te bakan oldu; yerine kim geldi bilinmiyor)
#   26. dönem (2015-2018) — Süreyya Sadi Bilgiç: TOSYÖV ziyareti (Nisan 2016) + Wikipedia
#   27. dönem (2018-2023):
#     2019: Süreyya Sadi Bilgiç (2019 bütçe görüşmeleri Ekim-Kasım 2018, Elvan Şubat 2019'da başladı)
#     2020: Lütfi Elvan (24 Şubat 2019 seçildi — AA.com.tr)
#     2021-2023: Cevdet Yılmaz (10 Kasım 2020 seçildi — AA.com.tr)
#   28. dönem (2023+) — Mehmet Muş: Wikipedia + corpus kanıtı
#
# NA satırlar: R/pbk_baskan_yil.R'yi güncelleyip 13_baskan_eslestir.R'yi yeniden çalıştır.

library(tibble)

pbk_baskan_yil <- tribble(
  ~butce_yili, ~pbk_baskan_kanonik,
  # 23. dönem (Temmuz 2007 – Haziran 2011)
  2009L,  "SAİT AÇBA",
  2010L,  "SAİT AÇBA",
  2011L,  "SAİT AÇBA",
  # 24. dönem (Haziran 2011 – Haziran 2015) — Lütfi Elvan Aralık 2013'e kadar
  2012L,  "LÜTFİ ELVAN",
  2013L,  "LÜTFİ ELVAN",
  2014L,  "LÜTFİ ELVAN",
  2015L,  NA_character_,   # 24. dönem sonu: doğrulanamadı (Mehmet Ülger?)
  # 26. dönem (Kasım 2015 – Haziran 2018)
  2016L,  "SÜREYYA SADİ BİLGİÇ",
  2017L,  "SÜREYYA SADİ BİLGİÇ",
  2018L,  "SÜREYYA SADİ BİLGİÇ",
  # 27. dönem (Haziran 2018 – Temmuz 2023)
  # 2019 bütçe görüşmeleri (Eki–Kas 2018) henüz Bilgiç döneminde
  2019L,  "SÜREYYA SADİ BİLGİÇ",
  # 2020 bütçe görüşmeleri (Eki–Kas 2019) Elvan döneminde (Şub 2019'dan itibaren)
  2020L,  "LÜTFİ ELVAN",
  # 2021 bütçe görüşmeleri (Eki–Kas 2020) Elvan → Yılmaz geçişi; Yılmaz baskın
  2021L,  "CEVDET YILMAZ",
  2022L,  "CEVDET YILMAZ",
  2023L,  "CEVDET YILMAZ",
  # 28. dönem (Temmuz 2023+)
  2024L,  "MEHMET MUŞ",
  2025L,  "MEHMET MUŞ"
)
