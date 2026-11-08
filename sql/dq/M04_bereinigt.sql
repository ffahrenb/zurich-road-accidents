-- id: DQ-M04
-- quelle: meteo
-- dimension: Gültigkeit
-- schwere: WARN
-- toleranz_pct: 5
-- titel_de: Messwerte sind vom Amt als «bereinigt» validiert (nicht provisorisch)
-- titel_en: Measurements are validated by the agency (not provisional)
SELECT
    count(*) AS n_tested,
    count_if(status <> 'bereinigt') AS n_failed
FROM raw_meteo;
