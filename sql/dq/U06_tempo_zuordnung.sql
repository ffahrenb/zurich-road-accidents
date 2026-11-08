-- id: DQ-U06
-- quelle: unfaelle
-- dimension: Vollständigkeit
-- schwere: WARN
-- toleranz_pct: 10
-- titel_de: Unfallort kann einem Strassenabschnitt mit signalisiertem Tempo zugeordnet werden (≤ 25 m)
-- titel_en: Accident can be matched to a road section with a speed limit (≤ 25 m)
SELECT
    count(*) AS n_tested,
    count_if(tempo_code IS NULL) AS n_failed
FROM mart_unfaelle;
