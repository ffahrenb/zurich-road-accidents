-- id: DQ-M02
-- quelle: meteo
-- dimension: Plausibilität
-- schwere: WARN
-- toleranz_pct: 0.1
-- titel_de: Rohwerte in physikalisch plausiblen Bereichen (Ausreisser werden in Staging entfernt)
-- titel_en: Raw values within physically plausible ranges (outliers are removed in staging)
SELECT
    count(*) AS n_tested,
    count_if(
        (parameter = 'T' AND wert NOT BETWEEN -30 AND 45)
        OR (parameter = 'RainDur' AND wert NOT BETWEEN 0 AND 60)
        OR (parameter = 'Hr' AND wert NOT BETWEEN 0 AND 100.5)
        OR (parameter = 'WVv' AND wert NOT BETWEEN 0 AND 60)
    ) AS n_failed,
    'Feuchte > 100.5 %: ' || count_if(parameter = 'Hr' AND wert > 100.5)
    || ', Regendauer > 60 min/h: ' || count_if(parameter = 'RainDur' AND wert > 60) AS detail
FROM raw_meteo;
