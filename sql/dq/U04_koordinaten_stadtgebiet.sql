-- id: DQ-U04
-- quelle: unfaelle
-- dimension: Gültigkeit
-- schwere: STOP
-- titel_de: Koordinaten liegen im Rechteck um die Stadt Zürich (LV95)
-- titel_en: Coordinates lie within the bounding box of the City of Zurich (LV95)
SELECT
    count(*) AS n_tested,
    count_if(
        e_lv95 NOT BETWEEN 2676000 AND 2690000
        OR n_lv95 NOT BETWEEN 1241000 AND 1255000
    ) AS n_failed
FROM stg_unfaelle;
