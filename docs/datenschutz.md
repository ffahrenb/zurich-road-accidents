# Datenschutz

Hintergrund und Entscheid: ADR 0004. Kurz: Die offenen Unfalldaten kennen nur Jahr, Monat,
Wochentag und Stunde. Die private Datei der Stadt Zürich enthält exakte Zeitpunkte. Jede
Veröffentlichung mit Datumsbezug würde erlauben, öffentliche Zeilen einem exakten Datum
zuzuordnen. Datenschutz ist deshalb in mehreren Schichten eingebaut, die einzeln ausfallen dürfen.

## Massnahmen

1. Private Datei ausserhalb des Repositorys. Sie wird nur zur Laufzeit read-only nach
   `/private/unfaelle.csv` gemountet (`make run` mit `ZH_PRIVATE_ACCIDENTS`). Sie ist nicht im
   Image und nicht in CI. `.gitignore` sperrt `*unfaelle*.csv`, `*.duckdb` und `data/`.
2. Pre-Commit-Hook (`tools/privacy-precommit.sh`, installieren mit `make hooks`). Blockiert
   Dateinamen `*unfaelle*.csv` und `*.duckdb`, jede Datei mit dem SHA-256 der privaten Datei und
   jede Datei, die `timestampOriginal` oder `ts_lokal` enthält (Code, Tests, Docs ausgenommen).
3. Export-Allowlist (`config/export.yml`). Nur deklarierte Tabellen und Spalten verlassen das
   Warehouse; Track X nur über drei benannte Dateien.
4. Mindestzellgrösse 10 (`trackx.min_cell`). Klassen mit weniger als 10 Unfällen oder weniger als
   10 Stunden werden nicht veröffentlicht.
5. Nur Koeffizienten, keine Modellobjekte. Gefittete Modelle enthalten Trainingszeilen;
   `wetter_modell.json` enthält Koeffizienten und Kennzahlen, keine Daten (Test begrenzt Grösse und
   verbietet Datenfelder).
6. Grobe Klassen statt Werte: Track X ist nur nach Regenklasse x Temperaturklasse gegliedert.
7. Privacy-Gate-Tests (unten), die in CI ohne private Daten laufen und im Zweifel scheitern.

## Privacy-Gate (`tests/testthat/test-privacy.R`)

Fail-closed: Was nicht ausdrücklich erlaubt ist, ist ein Fehler.

- Jede Datei unter `export/` ist deklariert (`export/data/<key>.<format>` aus `export.yml`,
  `unfaelle_punkte.geojson`, `quartiere.geojson`), liegt unter `export/modell|dq|meta/` oder ist
  eine der drei Track-X-Dateien.
- CSV-/Parquet-Spalten in `export/data` sind Teilmenge der Allowlist; Karten-Punkte tragen nur
  `j, s, v, f, m` (Jahr, Schwere, Velo, Fussgänger, Motorrad).
- Kein versioniertes, exportiertes oder gebautes (`site/_site`) File enthält `timestampOriginal`
  oder `ts_lokal`. `R/`, `sql/`, `tests/`, `tools/`, `docs/`, `*.md`, `*.qmd` sind ausgenommen,
  weil sie die Namen legitim erwähnen.
- Keine versionierte Datei hat den SHA-256 der privaten Datei.
- `wetter_klassen.csv`: Spalten genau `regen, temperatur, stunden, unfaelle, unfaelle_pro_stunde`;
  alle Zeilen mit `unfaelle >= 10` und `stunden >= 10`.
- Track-X-CSVs enthalten kein Datum (`YYYY-MM-DD`, `TT.MM.JJJJ`) und keine datumsähnlichen
  Spaltennamen (date, datum, ts, tag, woche, day, week).
- Join-Angriff: Kein Track-X-CSV hat eine Spalte `jahr, monat, wochentag, stunde, datum,
  unfall_id, lon, lat, quartier*`. Begründung: Öffentliche Zeilen tragen genau diese Attribute.
  Hätte ein Track-X-Output eine davon als Schlüssel, könnte man ihn mit den öffentlichen Zeilen
  verknüpfen und das private Attribut (Tag, Wetter dieser Stunde) einer Zeile zuordnen.
  Erlaubt sind nur Schlüssel auf Wetterklassen, die tausende Stunden teilen.

Ohne `export/` werden die Export-Tests übersprungen; die Prüfungen auf versionierte Dateien
(`git ls-files`) laufen immer.

## Das Gate testet sich selbst

`test-privacy-selftest.R` baut ein gültiges Verzeichnis in einem Temp-Ordner (Wurzel über
`ZH_PRIVACY_ROOT`), prüft, dass das Gate besteht, und dass es bei 15 gezielt eingebauten
Verstössen scheitert (Stray-Datei, Zusatzspalte, Zeitstempelname, SHA-Treffer, Zelle < 10, Datum,
Join-Schlüssel, ...). Die Fake-Dateien werden nicht committet.

## Restrisiken

Die Tests erkennen bekannte Muster, nicht jede denkbare Offenlegung. Neue Track-X-Ausgaben
brauchen eine bewusste Review gegen ADR 0004, bevor sie in die Allowlist kommen.
