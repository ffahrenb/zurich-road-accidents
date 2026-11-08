-- id: DQ-B01
-- quelle: bevoelkerung
-- dimension: Vollständigkeit
-- schwere: WARN
-- titel_de: Für jedes Quartier und Jahr mit Unfällen gibt es eine Bevölkerungszahl
-- titel_en: Every quarter-year with accidents has a population figure
SELECT
    count(*) AS n_tested,
    count_if(einwohner IS NULL) AS n_failed
FROM mart_quartier;
