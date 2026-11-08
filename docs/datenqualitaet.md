# Datenqualität

Datenqualität ist hier eine Freigabebedingung (ADR 0005): Jede Prüfung erzeugt eine Zeile in
`dq_results`; verletzte STOP-Prüfungen stoppen die Pipeline über `dq_gate()`.

## Prüfquellen

| Art | Ort | Zweck |
|-----|-----|-------|
| `pointblank` | `dq/contracts/<quelle>.yml` | Datenvertrag: Spalten vorhanden, Pflichtfelder, Wertelisten, Bereiche. HTML-Bericht je Quelle in `export/dq/`. |
| `SQL` | `sql/dq/*.sql` | Fachliche Prüfungen auf raw/staging/mart. Metadaten im Dateikopf. |
| `Historie` | `R/dq.R` (`check_snapshot_delta`) | Vergleich mit dem letzten Snapshot (`export/dq/snapshot_history.csv`): DQ-S01 (WARN, > 1 % je Jahr), DQ-S02 (STOP, Gesamtbestand um mehr als 10 % geschrumpft). |
| `Historie` | `R/dq.R` (`check_year_range`) | Jahresbereich (`years.to: auto`, `R/years.R`) gegen `export/dq/jahresbereich.csv`: DQ-S03 (WARN, neuestes Unfalljahr unvollständig und ausgelassen), DQ-S04 (STOP, Bereich kleiner als im letzten Snapshot), DQ-S05 (WARN, eine Jahresquelle hinkt nach). |
| `Metadaten` | `R/dq.R` (`check_freshness`) | Aktualität gegenüber `cadence_days` in `config/sources.yml`. |

## Dimensionen

Vollständigkeit, Eindeutigkeit, Gültigkeit, Plausibilität, Konsistenz, Referenzielle Integrität,
Aktualität, Stabilität (Historie), Schema & Vertrag. Die ID-Präfixe zeigen die Quelle:
U Unfälle, M Meteo, L Luft, B Bevölkerung, G Geometrien, X Track X (nur mit privater Datei).

## Schweregrade

- STOP: Datenstand ist für die Veröffentlichung unbrauchbar. `dq_gate()` bricht ab.
- WARN: auffällig, wird im Bericht gezeigt, blockiert nicht.
- `toleranz_pct`: Anteil fehlerhafter Zeilen (`n_failed / n_tested`), bis zu dem die Prüfung
  trotzdem als PASS gilt. Standard 0. Kann eine Prüfung nicht laufen (`n_failed` ist NA), gilt sie
  als nicht bestanden.

## Neue SQL-Prüfung anlegen

1. Datei `sql/dq/<Prefix><Nr>_<name>.sql` anlegen, Kopfzeilen im Format `-- feld: wert`:

   ```sql
   -- id: DQ-U09
   -- quelle: unfaelle
   -- dimension: Gültigkeit
   -- schwere: STOP
   -- toleranz_pct: 0
   -- benoetigt: stg_unfaelle
   -- titel_de: Jahr liegt im Auswertungszeitraum
   -- titel_en: Year lies within the analysis period
   SELECT
       count(*) AS n_tested,
       count_if(jahr NOT BETWEEN {{year_from}} AND {{year_to}}) AS n_failed
   FROM stg_unfaelle;
   ```

2. Pflichtfelder im Kopf: `id` (eindeutig), `quelle`, `dimension`, `schwere` (STOP oder WARN),
   `titel_de`, `titel_en`. Optional: `toleranz_pct` (Standard 0) und `benoetigt` (Tabelle; fehlt
   sie, wird die Prüfung übersprungen, so bei Track X ohne private Datei).
3. Die Abfrage liefert genau eine Zeile mit `n_tested` und `n_failed`, optional `detail`.
   Parameter als `{{name}}`; ein nicht gefüllter Parameter bricht mit Fehler ab (`render_sql`).
4. Test mit kaputtem Fixture ergänzen (nächster Abschnitt).

Der Test `every sql/dq file carries the full header metadata` verlangt vollständige Köpfe und
eindeutige IDs.

## Prinzip: Test mit kaputtem Fixture

Eine Prüfung, die nie fehlgeschlagen ist, beweist nichts. `tests/testthat/test-dq-engine.R`
baut deshalb eine kleine DuckDB im Speicher (`raw_unfaelle`, `stg_unfaelle`, `stg_meteo`), führt die
echten Prüfdateien aus `sql/dq` aus und verfälscht je Test genau einen Wert:

| Defekt im Fixture | Erwartung |
|-------------------|-----------|
| doppelte Unfall-ID | DQ-U01 STOP |
| Pflichtfeld NULL | DQ-U02 STOP |
| Koordinate ausserhalb Zürich | DQ-U04 STOP |
| Temperatur 99.9 Grad nach Bereinigung | DQ-M05 STOP |
| Bestand gegenüber letztem Snapshot um > 10 % kleiner | DQ-S02 STOP, DQ-S01 WARN |
| Jahresbereich kleiner als im letzten Snapshot | DQ-S04 STOP |
| neuestes Unfalljahr < 80 % des Vorjahres | DQ-S03 WARN (Jahr wird ausgelassen) |
| Einwohnerzahl des Unfalljahres fehlt, Vorjahr fortgeschrieben | DQ-B03 WARN |

Dazu gelten: saubere Fixtures ergeben nur PASS, ein Defekt löst nur die zuständige Prüfung aus,
`dq_gate()` bricht bei STOP ab und lässt WARN/PASS durch. Dasselbe Prinzip gilt für das
Datenschutz-Gate (`test-privacy-selftest.R`).

Ausführen: `make test`.
