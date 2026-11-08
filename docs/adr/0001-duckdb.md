# ADR 0001: DuckDB als Analyse-Datenbank

Status: angenommen, 2026-11-08

## Kontext

Die Pipeline verarbeitet rund 10^5 Unfälle, einige Millionen Stundenwerte Meteo/Luft sowie
Geodaten (Quartiere, Schulen, Tempozonen). Ein Mehrbenutzer-Server wird nicht gebraucht:
Eine Person baut das Warehouse, das Ergebnis sind statische Dateien auf GitHub Pages.
Die Transformationslogik soll als SQL lesbar und prüfbar sein, räumliche Verknüpfungen
(Unfall in Quartier, Schule im Umkreis, Tempozone) sind zentral.

## Entscheid

DuckDB (eingebettet, eine Datei `data/warehouse.duckdb`) mit den Core-Extensions `spatial`
und `icu`. Alle Transformationen liegen als SQL-Dateien unter `sql/`; R setzt nur Parameter
ein (`render_sql()`) und führt die Dateien in fester Reihenfolge aus. Die Extensions werden
beim Image-Build nach `/opt/duckdb_extensions` installiert, zur Laufzeit wird kein Code
nachgeladen (`autoinstall_known_extensions = false`).

## Konsequenzen

- Kein Datenbankserver, kein Betrieb; das Warehouse ist jederzeit aus den Rohdaten neu baubar
  und wird nicht versioniert (`*.duckdb` ist in `.gitignore` und im Pre-Commit-Hook gesperrt).
- Parquet, CSV und GeoJSON lassen sich direkt lesen und schreiben; der Export ist ein `COPY`.
- SQL ist linter-fähig (sqlfluff, Dialekt `duckdb`) und für Fachleute ohne R-Kenntnisse lesbar.
- Einzelschreiber-Modell: parallele Schreibzugriffe sind nicht vorgesehen. Die DQ-Prüfung
  öffnet die Datei read-only.
- DuckDB-Dateiformat und Extensions sind versionsgebunden; das Image fixiert beides
  (siehe `docs/pipeline.md`, Reproduzierbarkeit).
- Alternative PostGIS wurde verworfen: mehr Betriebsaufwand ohne Nutzen bei dieser Datenmenge.
