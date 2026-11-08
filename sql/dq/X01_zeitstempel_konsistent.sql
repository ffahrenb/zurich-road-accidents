-- id: DQ-X01
-- quelle: privat
-- dimension: Konsistenz
-- schwere: STOP
-- benoetigt: stg_x_zeit
-- titel_de: Exakte Zeitstempel stimmen mit Jahr, Monat, Wochentag und Stunde der öffentlichen Daten überein
-- titel_en: Exact timestamps agree with year, month, weekday and hour of the public data
SELECT
    count(*) AS n_tested,
    count_if(
        year(x.ts_lokal) <> u.jahr OR month(x.ts_lokal) <> u.monat
        OR isodow(x.ts_lokal) <> u.wochentag OR hour(x.ts_lokal) <> u.stunde
    ) AS n_failed
FROM stg_x_zeit AS x
INNER JOIN stg_unfaelle AS u ON x.unfall_id = u.unfall_id;
