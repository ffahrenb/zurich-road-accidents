-- id: DQ-U03
-- quelle: unfaelle
-- dimension: Gültigkeit
-- schwere: STOP
-- titel_de: Codes liegen in den erlaubten Wertelisten (Schwere, Monat, Wochentag, Stunde)
-- titel_en: Codes are within allowed value lists (severity, month, weekday, hour)
SELECT
    count(*) AS n_tested,
    count_if(
        schwere_code NOT IN ('as1', 'as2', 'as3', 'as4')
        OR monat NOT BETWEEN 1 AND 12
        OR wochentag NOT BETWEEN 1 AND 7
        OR stunde NOT BETWEEN 0 AND 23
    ) AS n_failed
FROM stg_unfaelle;
