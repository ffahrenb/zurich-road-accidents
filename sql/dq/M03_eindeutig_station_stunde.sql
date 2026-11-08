-- id: DQ-M03
-- quelle: meteo
-- dimension: Eindeutigkeit
-- schwere: STOP
-- titel_de: Pro Station, Stunde und Parameter genau ein Messwert
-- titel_en: Exactly one value per station, hour and parameter
SELECT
    count(*) AS n_tested,
    count(*) - (SELECT count(*) FROM (SELECT DISTINCT datum, standort, parameter FROM raw_meteo)) AS n_failed
FROM raw_meteo;
