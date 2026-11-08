-- id: DQ-G01
-- quelle: quartiere
-- dimension: Gültigkeit
-- schwere: WARN
-- toleranz_pct: 1
-- titel_de: Gelieferte Geometrien sind gültig (ungültige werden in Staging repariert)
-- titel_en: Delivered geometries are valid (invalid ones are repaired in staging)
SELECT
    sum(n) AS n_tested,
    sum(bad) AS n_failed,
    string_agg(layer || ': ' || bad, ', ') FILTER (WHERE bad > 0) AS detail
FROM (
    SELECT 'Quartiere' AS layer, count(*) AS n, count_if(NOT st_isvalid(geom)) AS bad FROM raw_quartiere
    UNION ALL
    SELECT 'Schulen', count(*), count_if(NOT st_isvalid(geom)) FROM raw_schulen
    UNION ALL
    SELECT 'Tempo', count(*), count_if(NOT st_isvalid(geom)) FROM raw_tempo
);
