-- id: DQ-L01
-- quelle: luft
-- dimension: Gültigkeit
-- schwere: WARN
-- toleranz_pct: 0.5
-- titel_de: Schadstoffwerte nicht negativ und unter 1000 µg/m³
-- titel_en: Pollutant values not negative and below 1000 µg/m³
SELECT
    count(*) AS n_tested,
    count_if(no2_ugm3 < 0 OR no2_ugm3 > 1000 OR o3_ugm3 < 0 OR o3_ugm3 > 1000) AS n_failed
FROM stg_luft;
