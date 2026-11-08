-- MART: aggregates that feed the website (public track only).

CREATE OR REPLACE TABLE mart_jahr AS
SELECT
    jahr,
    schwere_kurz,
    count(*) AS unfaelle,
    count_if(mit_velo) AS mit_velo,
    count_if(mit_fussgaenger) AS mit_fussgaenger,
    count_if(mit_motorrad) AS mit_motorrad
FROM mart_unfaelle
GROUP BY ALL
ORDER BY ALL;

CREATE OR REPLACE TABLE mart_zeitmuster AS
SELECT
    wochentag,
    stunde,
    count(*) AS unfaelle,
    count_if(personenschaden) AS mit_personenschaden,
    count_if(mit_velo) AS mit_velo,
    count_if(mit_fussgaenger) AS mit_fussgaenger
FROM mart_unfaelle
GROUP BY ALL
ORDER BY ALL;

-- Rates per 1000 inhabitants: accidents of a year divided by population at year end.
CREATE OR REPLACE TABLE mart_quartier AS
WITH unf AS (
    SELECT
        quartier_nr,
        jahr,
        count(*) AS unfaelle,
        count_if(personenschaden) AS mit_personenschaden
    FROM mart_unfaelle
    WHERE quartier_nr IS NOT NULL
    GROUP BY ALL
)

SELECT
    q.quartier_nr,
    q.quartier,
    q.kreis_nr,
    unf.jahr,
    b.einwohner,
    coalesce(unf.unfaelle, 0) AS unfaelle,
    coalesce(unf.mit_personenschaden, 0) AS mit_personenschaden,
    round(1000.0 * coalesce(unf.mit_personenschaden, 0) / b.einwohner, 2)
        AS personenschaden_pro_1000
FROM stg_quartiere AS q
INNER JOIN unf ON q.quartier_nr = unf.quartier_nr
LEFT JOIN stg_bevoelkerung AS b
    ON unf.quartier_nr = b.quartier_nr AND unf.jahr = b.jahr;

CREATE OR REPLACE TABLE mart_tempo AS
SELECT
    tempo_klasse,
    count(*) AS unfaelle,
    count_if(personenschaden) AS mit_personenschaden,
    round(100.0 * count_if(personenschaden) / count(*), 1) AS anteil_personenschaden_pct
FROM mart_unfaelle
GROUP BY ALL
ORDER BY ALL;

-- Monthly weather (public track): weather is aggregated to month level,
-- because public accident data has no day-of-month.
CREATE OR REPLACE TABLE mart_wetter_monat AS
WITH w AS (
    SELECT
        year(ts_utc + INTERVAL 1 HOUR) AS jahr,
        month(ts_utc + INTERVAL 1 HOUR) AS monat,
        avg(temperatur_c) AS temperatur_c,
        count_if(regen_min > 0) AS regenstunden
    FROM stg_meteo
    WHERE station = '{{station}}'
    GROUP BY ALL
),

u AS (
    SELECT
        jahr,
        monat,
        count(*) AS unfaelle,
        count_if(personenschaden) AS mit_personenschaden,
        count_if(mit_velo) AS mit_velo
    FROM mart_unfaelle
    GROUP BY ALL
)

SELECT
    u.*,
    round(w.temperatur_c, 2) AS temperatur_c,
    w.regenstunden
FROM u
LEFT JOIN w ON u.jahr = w.jahr AND u.monat = w.monat
ORDER BY u.jahr, u.monat;
