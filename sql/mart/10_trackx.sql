-- TRACK X (exact date, private input, local only).
-- Builds a complete hourly series in UTC: one row per hour 2011-2021,
-- with the number of accidents and the weather of that hour.
-- Nothing from this table leaves the machine; only model results do.

CREATE OR REPLACE TABLE stg_x_zeit AS
SELECT
    p.accidentuid AS unfall_id,
    p.timestamporiginal::TIMESTAMP AS ts_lokal,
    (p.timestamporiginal::TIMESTAMP AT TIME ZONE 'Europe/Zurich')::TIMESTAMP AS ts_utc
FROM raw_x_private AS p
WHERE nullif(p.timestamporiginal, '') IS NOT NULL;

CREATE OR REPLACE TABLE mart_x_stunden AS
WITH
stunden AS (
    SELECT unnest(generate_series(
        TIMESTAMP '{{x_from}}', TIMESTAMP '{{x_to}}', INTERVAL 1 HOUR
    )) AS ts_utc
),

unf AS (
    SELECT
        date_trunc('hour', x.ts_utc) AS ts_utc,
        count(*) AS unfaelle,
        count_if(m.personenschaden) AS mit_personenschaden,
        count_if(m.mit_velo) AS mit_velo
    FROM stg_x_zeit AS x
    INNER JOIN mart_unfaelle AS m ON x.unfall_id = m.unfall_id
    GROUP BY ALL
),

w AS (
    SELECT * FROM stg_meteo WHERE station = '{{station}}'
)

SELECT
    s.ts_utc,
    (s.ts_utc AT TIME ZONE 'UTC') AT TIME ZONE 'Europe/Zurich' AS ts_lokal,
    coalesce(unf.unfaelle, 0) AS unfaelle,
    coalesce(unf.mit_personenschaden, 0) AS mit_personenschaden,
    coalesce(unf.mit_velo, 0) AS mit_velo,
    w.regen_min,
    w.temperatur_c,
    w.wind_ms
FROM stunden AS s
LEFT JOIN unf ON s.ts_utc = unf.ts_utc
LEFT JOIN w ON s.ts_utc = w.ts_utc;
