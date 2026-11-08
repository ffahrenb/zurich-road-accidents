-- id: DQ-B02
-- quelle: bevoelkerung
-- dimension: Referenzielle Integrität
-- schwere: STOP
-- titel_de: Quartiernummern der Bevölkerungsstatistik existieren in den Geodaten
-- titel_en: Quarter numbers in the population statistics exist in the geodata
SELECT
    count(*) AS n_tested,
    count_if(q.quartier_nr IS NULL) AS n_failed
FROM (SELECT DISTINCT quartier_nr FROM stg_bevoelkerung) AS b
LEFT JOIN stg_quartiere AS q ON b.quartier_nr = q.quartier_nr;
