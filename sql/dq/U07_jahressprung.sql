-- id: DQ-U07
-- quelle: unfaelle
-- dimension: Plausibilität
-- schwere: WARN
-- titel_de: Keine Jahresveränderung der Unfallzahl über ±25 % (Strukturbruch-Detektor)
-- titel_en: No year-on-year change in accident count above ±25 % (structural-break detector)
WITH y AS (
    SELECT
        jahr,
        count(*) AS n
    FROM stg_unfaelle
    GROUP BY jahr
),

d AS (
    SELECT
        jahr,
        n,
        n / lag(n) OVER (ORDER BY jahr) - 1 AS veraenderung
    FROM y
)

SELECT
    count(veraenderung) AS n_tested,
    count_if(abs(veraenderung) > 0.25) AS n_failed,
    string_agg(
        CASE WHEN abs(veraenderung) > 0.25
            THEN jahr || ': ' || round(100 * veraenderung) || ' %' END,
        '; '
    ) AS detail
FROM d;
