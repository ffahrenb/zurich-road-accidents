-- id: DQ-M03
-- quelle: meteo
-- dimension: Eindeutigkeit
-- schwere: STOP
-- titel_de: Pro Station, Stunde und Parameter genau ein Messwert
-- titel_en: Exactly one value per station, hour and parameter
SELECT
    count(*) AS n_tested,
    count(*) - count(DISTINCT (datum, standort, parameter)) AS n_failed
FROM raw_meteo;
