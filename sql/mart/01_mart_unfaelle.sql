-- MART: one row per accident, enriched with place attributes.
-- Spatial joins in LV95 (metres). Each enrichment is LEFT JOIN, so an accident
-- is never lost because a geodata layer does not cover it (DQ measures coverage).
CREATE OR REPLACE TABLE mart_unfaelle AS
WITH
quartier AS (
    SELECT
        u.unfall_id,
        q.quartier_nr,
        q.quartier,
        q.kreis_nr
    FROM stg_unfaelle AS u
    INNER JOIN stg_quartiere AS q ON st_contains(q.geom, u.geom)
),

schule AS (
    SELECT
        u.unfall_id,
        min(st_distance(u.geom, s.geom)) AS distanz_schule_m
    FROM stg_unfaelle AS u
    INNER JOIN stg_schulen AS s ON st_dwithin(u.geom, s.geom, {{school_radius_m}})
    GROUP BY u.unfall_id
),

tempo AS (
    SELECT
        u.unfall_id,
        arg_min(t.tempo_code, st_distance(u.geom, t.geom)) AS tempo_code,
        arg_min(t.temporegime, st_distance(u.geom, t.geom)) AS temporegime,
        min(st_distance(u.geom, t.geom)) AS distanz_tempo_m
    FROM stg_unfaelle AS u
    INNER JOIN stg_tempo AS t ON st_dwithin(u.geom, t.geom, {{tempo_radius_m}})
    GROUP BY u.unfall_id
)

SELECT
    u.* EXCLUDE (geom),
    q.quartier_nr,
    q.quartier,
    q.kreis_nr,
    s.distanz_schule_m IS NOT NULL AS nahe_schule,
    t.tempo_code,
    t.temporegime,
    t.distanz_tempo_m,
    CASE u.schwere_code
        WHEN 'as1' THEN 'Getötete'
        WHEN 'as2' THEN 'Schwerverletzte'
        WHEN 'as3' THEN 'Leichtverletzte'
        WHEN 'as4' THEN 'Sachschaden'
    END AS schwere_kurz,
    u.schwere_code IN ('as1', 'as2', 'as3') AS personenschaden,
    CASE
        WHEN t.tempo_code IS NULL THEN 'unbekannt'
        WHEN t.tempo_code IN ('T20', 'T30', 'T30N0') THEN 'Tempo 30 oder tiefer'
        WHEN t.tempo_code IN ('T50', 'T50N30') THEN 'Tempo 50'
        WHEN t.tempo_code IN ('T60', 'T70', 'T80', 'T100', 'T120') THEN 'Tempo 60+'
        ELSE 'andere'
    END AS tempo_klasse,
    st_x(st_transform(u.geom, 'EPSG:2056', 'EPSG:4326', always_xy := TRUE)) AS lon,
    st_y(st_transform(u.geom, 'EPSG:2056', 'EPSG:4326', always_xy := TRUE)) AS lat
FROM stg_unfaelle AS u
LEFT JOIN quartier AS q ON u.unfall_id = q.unfall_id
LEFT JOIN schule AS s ON u.unfall_id = s.unfall_id
LEFT JOIN tempo AS t ON u.unfall_id = t.unfall_id;
