-- STAGING: hourly meteo + air quality, long -> wide per station and hour.
-- Source timestamps carry a fixed +01:00 offset (CET, no daylight saving).
-- They are converted to UTC here, so joins with local-time data are DST-correct.
-- Cleansing rule: physically impossible values (detected by DQ-M02) are set to
-- NULL, never silently corrected. DQ-M05 verifies the result.
CREATE OR REPLACE TABLE stg_meteo AS
SELECT
    strptime(datum, '%Y-%m-%dT%H:%M%z')::TIMESTAMP AS ts_utc,
    standort AS station,
    max(CASE WHEN parameter = 'T' AND wert BETWEEN -30 AND 45 THEN wert END) AS temperatur_c,
    max(CASE WHEN parameter = 'RainDur' AND wert BETWEEN 0 AND 60 THEN wert END) AS regen_min,
    max(CASE WHEN parameter = 'Hr' AND wert BETWEEN 0 AND 100.5 THEN wert END) AS feuchte_pct,
    max(CASE WHEN parameter = 'WVv' AND wert BETWEEN 0 AND 60 THEN wert END) AS wind_ms,
    max(CASE WHEN parameter = 'StrGlo' THEN wert END) AS strahlung_wm2,
    max(CASE WHEN parameter = 'p' THEN wert END) AS druck_hpa,
    bool_and(status = 'bereinigt') AS bereinigt
FROM raw_meteo
GROUP BY ALL;

CREATE OR REPLACE TABLE stg_luft AS
SELECT
    strptime(datum, '%Y-%m-%dT%H:%M%z')::TIMESTAMP AS ts_utc,
    standort AS station,
    max(CASE WHEN parameter = 'NO2' THEN wert END) AS no2_ugm3,
    max(CASE WHEN parameter = 'O3' THEN wert END) AS o3_ugm3,
    max(CASE WHEN parameter = 'PM10' THEN wert END) AS pm10_ugm3,
    max(CASE WHEN parameter = 'PM2.5' THEN wert END) AS pm25_ugm3
FROM raw_luft
GROUP BY ALL;
