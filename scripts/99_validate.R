library(arrow); library(dplyr)

validate_corpus <- function(
    parquet_yol = "data/processed/konusmalar_metadata.parquet",
    baseline_yol = NULL) {

  k <- read_parquet(parquet_yol)

  # --- Yil bazinda metrikler ---
  metrik <- k |> group_by(butce_yili) |>
    summarise(
      satir = n(),
      pdf = n_distinct(dosya_kaynak),
      satir_per_pdf = round(n() / n_distinct(dosya_kaynak)),
      kelime = sum(kelime_sayisi, na.rm = TRUE),
      ort_kelime = round(mean(kelime_sayisi, na.rm = TRUE), 1),
      medyan_kelime = median(kelime_sayisi, na.rm = TRUE),
      p99_kelime = quantile(kelime_sayisi, .99, na.rm = TRUE),
      maks_kelime = max(kelime_sayisi, na.rm = TRUE),
      baskan_pay = round(100*mean(rol == "baskan"), 1),
      mv_pay = round(100*mean(rol == "milletvekili"), 1),
      bakan_pay = round(100*mean(rol == "bakan"), 1),
      burokrat_pay = round(100*mean(rol == "burokrat"), 2),
      mv_eslesme = round(100*mean(!is.na(mv_sicil) & rol == "milletvekili") /
                         pmax(mean(rol == "milletvekili"), 1e-9), 1),
      .groups = "drop"
    )

  # --- Kalinti kontrolleri ---
  kontrol <- data.frame(
    kontrol = c("bozuk_karakter", "altbilgi_sizinti",
                "gomulu_baskan_basligi", "mv_etiketli_kurum"),
    n = c(
      sum(grepl("Ġ|Ģ|ġ", k$metin)),
      sum(grepl("Tutanak Hizmetleri|Tutanak Müdürlüğü", k$metin)),
      sum(grepl("BAŞKAN *[-–]", k$metin)),
      sum(k$rol == "milletvekili" &
          grepl("MÜSTEŞAR|RTÜK|BDDK|SPK|REKABET KURUMU|DENETÇİ",
                k$konusmaci_ham, ignore.case = TRUE))
    ),
    beklenen = c("0", "<5 (mesru gecisler)", "dusuk (bilinen sinirlilik)", "0")
  )

  # --- Anormal deger bayraklari ---
  bayrak <- list()

  # Baskan payi bandi disinda mi
  b <- metrik |> filter(baskan_pay < 20 | baskan_pay > 55)
  if (nrow(b) > 0) bayrak$baskan_pay <- b |> select(butce_yili, baskan_pay)

  # PDF basina satir yogunlugu aykiri mi (medyanin yarisi alti / iki kati ustu)
  med <- median(metrik$satir_per_pdf)
  b <- metrik |> filter(satir_per_pdf < med*0.5 | satir_per_pdf > med*2)
  if (nrow(b) > 0) bayrak$satir_yogunluk <- b |> select(butce_yili, satir_per_pdf)

  # Ortalama uzunluk aykiri mi
  med_ort <- median(metrik$ort_kelime)
  b <- metrik |> filter(ort_kelime < med_ort*0.5 | ort_kelime > med_ort*2)
  if (nrow(b) > 0) bayrak$ort_uzunluk <- b |> select(butce_yili, ort_kelime)

  # Ust kuyruk: p99 aykiri mi (birlesmis dev konusma belirtisi)
  med_p99 <- median(metrik$p99_kelime)
  b <- metrik |> filter(p99_kelime > med_p99*2)
  if (nrow(b) > 0) bayrak$ust_kuyruk <- b |> select(butce_yili, p99_kelime)

  # Eslesme dusuk mu
  b <- metrik |> filter(mv_eslesme < 90)
  if (nrow(b) > 0) bayrak$eslesme <- b |> select(butce_yili, mv_eslesme)

  # --- Dosya bazinda yogunluk (dosya duzeyi parse hatasi icin) ---
  dosya_metrik <- k |> group_by(dosya_kaynak) |>
    summarise(satir = n(), ort_kelime = round(mean(kelime_sayisi)),
              .groups = "drop")
  med_dosya <- median(dosya_metrik$satir)
  aykiri_dosya <- dosya_metrik |>
    filter(satir < med_dosya*0.3 | ort_kelime > median(dosya_metrik$ort_kelime)*2.5)

  # --- Rapor ---
  cat("=== KORPUS DOGRULAMA ===\n")
  cat("Toplam satir:", nrow(k), "| Kelime:", sum(k$kelime_sayisi, na.rm=TRUE), "\n\n")

  cat("--- Yil bazinda metrikler ---\n")
  print(as.data.frame(metrik))

  cat("\n--- Kalinti kontrolleri ---\n")
  print(kontrol)

  cat("\n--- Bayraklar ---\n")
  if (length(bayrak) == 0) {
    cat("Bayrak yok.\n")
  } else {
    for (n in names(bayrak)) {
      cat("\n[", n, "]\n"); print(as.data.frame(bayrak[[n]]))
    }
  }

  cat("\n--- Aykiri dosyalar (", nrow(aykiri_dosya), ") ---\n")
  if (nrow(aykiri_dosya) > 0) print(as.data.frame(head(aykiri_dosya, 20)))

  # --- Baseline karsilastirmasi ---
  if (!is.null(baseline_yol) && file.exists(baseline_yol)) {
    bl <- read.csv(baseline_yol)
    cat("\n--- Baseline karsilastirmasi ---\n")
    kars <- metrik |> select(butce_yili, satir, ort_kelime, baskan_pay) |>
      left_join(bl |> select(butce_yili, satir_bl = satir,
                             ort_bl = ort_kelime, baskan_bl = baskan_pay),
                by = "butce_yili") |>
      mutate(satir_fark = satir - satir_bl,
             ort_fark = round(ort_kelime - ort_bl, 1),
             baskan_fark = round(baskan_pay - baskan_bl, 1))
    print(as.data.frame(kars))
  }

  invisible(list(metrik = metrik, kontrol = kontrol, bayrak = bayrak,
                 aykiri_dosya = aykiri_dosya))
}

# Dogrudan calistirilirsa
# Baseline dosyasi icin: data/processed/baseline_v1.1.0.csv (bkz. CHANGELOG.md)
if (sys.nframe() == 0) {
  validate_corpus(baseline_yol = "data/processed/baseline_v1.1.0.csv")
}
