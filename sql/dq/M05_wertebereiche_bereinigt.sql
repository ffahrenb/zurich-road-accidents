-- id: DQ-M05
-- quelle: meteo
-- dimension: Gültigkeit
-- schwere: STOP
-- titel_de: Nach der Bereinigung liegen alle Messwerte in plausiblen Bereichen
-- titel_en: After cleansing, all measurements lie within plausible ranges
SELECT
    count(*) AS n_tested,
    count_if(
        temperatur_c NOT BETWEEN -30 AND 45
        OR regen_min NOT BETWEEN 0 AND 60
        OR feuchte_pct NOT BETWEEN 0 AND 100.5
        OR wind_ms NOT BETWEEN 0 AND 60
    ) AS n_failed
FROM stg_meteo;
