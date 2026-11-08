-- RAW layer: 1:1 copies of the downloaded files. No cleaning, no renaming.
-- File lists are injected by the pipeline (double-brace placeholders).

CREATE OR REPLACE TABLE raw_unfaelle AS
SELECT * FROM read_parquet({{unfaelle}});

CREATE OR REPLACE TABLE raw_meteo AS
SELECT *
FROM read_csv(
    {{meteo}},
    header = TRUE,
    filename = TRUE,
    nullstr = 'NA',
    columns = {
        'Datum': 'VARCHAR', 'Standort': 'VARCHAR', 'Parameter': 'VARCHAR',
        'Intervall': 'VARCHAR', 'Einheit': 'VARCHAR', 'Wert': 'DOUBLE',
        'Status': 'VARCHAR'
    }
);

CREATE OR REPLACE TABLE raw_luft AS
SELECT *
FROM read_csv(
    {{luft}},
    header = TRUE,
    filename = TRUE,
    nullstr = 'NA',
    columns = {
        'Datum': 'VARCHAR', 'Standort': 'VARCHAR', 'Parameter': 'VARCHAR',
        'Intervall': 'VARCHAR', 'Einheit': 'VARCHAR', 'Wert': 'DOUBLE',
        'Status': 'VARCHAR'
    }
);

CREATE OR REPLACE TABLE raw_bevoelkerung AS
SELECT * FROM read_csv({{bevoelkerung}}, header = TRUE);

CREATE OR REPLACE TABLE raw_quartiere AS
SELECT * FROM st_read({{quartiere}});

CREATE OR REPLACE TABLE raw_schulen AS
SELECT * FROM st_read({{schulen}});

CREATE OR REPLACE TABLE raw_tempo AS
SELECT * FROM st_read({{tempo}});
