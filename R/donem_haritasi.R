# R/donem_haritasi.R
# Bütçe yılı → TBMM dönemi lookup tablosu
# Bütçe görüşmeleri bir önceki yılın Kasım/Aralık ayında yapılır.
# 2016: erken seçim sonrası bütçe Ocak-Şubat 2016'ya kaydı → 26. dönem.
# 25. dönem (2015 Haz–Kas) bütçe görüşmesi yapmadı → haritada yok.

library(tibble)

donem_haritasi <- tribble(
  ~butce_yili, ~tbmm_donem,
  2009L,       23L,
  2010L,       23L,
  2011L,       23L,
  2012L,       24L,
  2013L,       24L,
  2014L,       24L,
  2015L,       24L,
  2016L,       26L,
  2017L,       26L,
  2018L,       26L,
  2019L,       27L,
  2020L,       27L,
  2021L,       27L,
  2022L,       27L,
  2023L,       27L,
  2024L,       28L,
  2025L,       28L
)
