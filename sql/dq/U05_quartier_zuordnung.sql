-- id: DQ-U05
-- quelle: unfaelle
-- dimension: Konsistenz
-- schwere: WARN
-- toleranz_pct: 0.5
-- titel_de: Jeder Unfall liegt in einem statistischen Quartier
-- titel_en: Every accident lies within a statistical quarter
SELECT
    count(*) AS n_tested,
    count_if(quartier_nr IS NULL) AS n_failed
FROM mart_unfaelle;
