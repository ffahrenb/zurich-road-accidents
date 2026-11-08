-- STAGING: population and geodata. WFS delivers WGS84 (lon/lat);
-- everything is projected to LV95 (EPSG:2056) so distances are in metres.
-- Invalid geometries (detected by DQ-G01) are repaired with ST_MakeValid;
-- DQ-G03 verifies the repaired layer.
CREATE OR REPLACE TABLE stg_bevoelkerung AS
SELECT
    stichtagdatjahr::INTEGER AS jahr,
    quarsort::INTEGER AS quartier_nr,
    quarlang AS quartier,
    anzbestwir::INTEGER AS einwohner
FROM raw_bevoelkerung;

CREATE OR REPLACE TABLE stg_quartiere AS
SELECT
    qnr::INTEGER AS quartier_nr,
    qname AS quartier,
    knr::INTEGER AS kreis_nr,
    st_makevalid(st_transform(geom, 'EPSG:4326', 'EPSG:2056', always_xy := TRUE)) AS geom
FROM raw_quartiere;

CREATE OR REPLACE TABLE stg_schulen AS
SELECT
    einheit AS schule,
    st_makevalid(st_transform(geom, 'EPSG:4326', 'EPSG:2056', always_xy := TRUE)) AS geom
FROM raw_schulen;

CREATE OR REPLACE TABLE stg_tempo AS
SELECT
    id AS abschnitt_id,
    lokalisationsname AS strasse,
    temporegime,
    temporegime_technical AS tempo_code,
    st_makevalid(st_transform(geom, 'EPSG:4326', 'EPSG:2056', always_xy := TRUE)) AS geom
FROM raw_tempo
WHERE temporegime_technical <> 'T0';   -- T0 = Fahrverbot, no through traffic
