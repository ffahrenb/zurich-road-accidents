-- id: DQ-U08
-- quelle: unfaelle
-- dimension: Aktualität
-- schwere: WARN
-- titel_de: Jüngstes Unfalljahr ist höchstens zwei Jahre alt
-- titel_en: Most recent accident year is at most two years old
SELECT
    1 AS n_tested,
    (max(accidentyear) < year(current_date) - 2)::INTEGER AS n_failed,
    'jüngstes Jahr: ' || max(accidentyear) AS detail
FROM raw_unfaelle;
