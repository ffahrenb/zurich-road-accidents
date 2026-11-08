-- id: DQ-G03
-- quelle: quartiere
-- dimension: Gültigkeit
-- schwere: STOP
-- titel_de: Nach der Reparatur sind alle Geometrien gültig
-- titel_en: After repair, all geometries are valid
SELECT
    sum(n) AS n_tested,
    sum(bad) AS n_failed
FROM (
    SELECT count(*) AS n, count_if(NOT st_isvalid(geom)) AS bad FROM stg_quartiere
    UNION ALL
    SELECT count(*), count_if(NOT st_isvalid(geom)) FROM stg_schulen
    UNION ALL
    SELECT count(*), count_if(NOT st_isvalid(geom)) FROM stg_tempo
);
