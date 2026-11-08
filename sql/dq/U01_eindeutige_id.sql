-- id: DQ-U01
-- quelle: unfaelle
-- dimension: Eindeutigkeit
-- schwere: STOP
-- titel_de: Jede Unfall-ID kommt genau einmal vor
-- titel_en: Every accident ID occurs exactly once
SELECT
    count(*) AS n_tested,
    count(*) - count(DISTINCT accidentuid) AS n_failed
FROM raw_unfaelle;
