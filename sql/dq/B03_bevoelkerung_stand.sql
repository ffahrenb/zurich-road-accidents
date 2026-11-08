-- id: DQ-B03
-- quelle: bevoelkerung
-- dimension: Aktualität
-- schwere: WARN
-- titel_de: Die Einwohnerzahl stammt aus dem Unfalljahr (sonst wird der neueste Stand fortgeschrieben)
-- titel_en: The population figure is from the accident year (otherwise the latest available year is carried forward)
SELECT
    count(*) AS n_tested,
    count_if(einwohner_jahr < jahr) AS n_failed,
    string_agg(DISTINCT jahr || ' mit Stand ' || einwohner_jahr, '; ') FILTER (WHERE einwohner_jahr < jahr) AS detail
FROM mart_quartier;
