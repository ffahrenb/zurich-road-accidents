-- id: DQ-X02
-- quelle: privat
-- dimension: Konsistenz
-- schwere: WARN
-- toleranz_pct: 1
-- benoetigt: mart_x_stunden
-- titel_de: Für jede Unfallstunde liegen Wetterdaten vor
-- titel_en: Weather data exist for every accident hour
SELECT
    sum(unfaelle) AS n_tested,
    sum(CASE WHEN regen_min IS NULL OR temperatur_c IS NULL THEN unfaelle ELSE 0 END) AS n_failed
FROM mart_x_stunden;
