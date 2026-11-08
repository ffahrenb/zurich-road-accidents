-- id: DQ-M01
-- quelle: meteo
-- dimension: Vollständigkeit
-- schwere: WARN
-- toleranz_pct: 1
-- titel_de: Referenzstation liefert für jede Stunde Temperatur und Regendauer
-- titel_en: Reference station delivers temperature and rain duration for every hour
WITH erwartet AS (
    SELECT unnest(generate_series(
        TIMESTAMP '{{year_from}}-01-01 00:00:00' - INTERVAL 1 HOUR,
        TIMESTAMP '{{year_to}}-12-31 22:00:00',
        INTERVAL 1 HOUR
    )) AS ts_utc
)

SELECT
    count(*) AS n_tested,
    count_if(m.temperatur_c IS NULL OR m.regen_min IS NULL) AS n_failed
FROM erwartet AS e
LEFT JOIN stg_meteo AS m
    ON e.ts_utc = m.ts_utc AND m.station = '{{station}}';
