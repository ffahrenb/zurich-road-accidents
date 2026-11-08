-- id: DQ-U02
-- quelle: unfaelle
-- dimension: Vollständigkeit
-- schwere: STOP
-- titel_de: Pflichtfelder (ID, Schwere, Zeit, Koordinaten) sind gefüllt
-- titel_en: Mandatory fields (id, severity, time, coordinates) are filled
SELECT
    count(*) AS n_tested,
    count_if(
        unfall_id IS NULL OR schwere_code IS NULL OR jahr IS NULL
        OR monat IS NULL OR wochentag IS NULL OR stunde IS NULL
        OR e_lv95 IS NULL OR n_lv95 IS NULL
    ) AS n_failed
FROM stg_unfaelle;
