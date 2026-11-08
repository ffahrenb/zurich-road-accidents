-- id: DQ-G02
-- quelle: quartiere
-- dimension: Vollständigkeit
-- schwere: STOP
-- titel_de: Alle 34 statistischen Quartiere sind vorhanden
-- titel_en: All 34 statistical quarters are present
SELECT
    34 AS n_tested,
    abs(34 - count(DISTINCT quartier_nr)) AS n_failed
FROM stg_quartiere;
