-- STAGING: accidents — typed, German column names, LV95 geometry (EPSG:2056).
CREATE OR REPLACE TABLE stg_unfaelle AS
SELECT
    accidentuid AS unfall_id,
    accidenttype AS typ_code,
    accidenttype_de AS typ,
    accidentseveritycategory AS schwere_code,
    accidentseveritycategory_de AS schwere,
    accidentinvolvingpedestrian AS mit_fussgaenger,
    accidentinvolvingbicycle AS mit_velo,
    accidentinvolvingmotorcycle AS mit_motorrad,
    roadtype_de AS strassenart,
    accidentyear::INTEGER AS jahr,
    accidentmonth::INTEGER AS monat,
    right(accidentweekday, 1)::INTEGER AS wochentag,      -- 1 = Montag (ISO)
    accidenthour::INTEGER AS stunde,                       -- Lokalzeit
    accidentlocation_chlv95_e::DOUBLE AS e_lv95,
    accidentlocation_chlv95_n::DOUBLE AS n_lv95,
    st_point(accidentlocation_chlv95_e, accidentlocation_chlv95_n) AS geom
FROM raw_unfaelle
WHERE accidentyear BETWEEN {{year_from}} AND {{year_to}};
