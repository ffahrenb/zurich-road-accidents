# ADR 0003: Schichten raw, staging, mart

Status: angenommen, 2026-11-08

## Kontext

Die Quellen sind uneinheitlich (Parquet, CSV pro Jahr, WFS-GeoJSON), mit Quellspalten in
CamelCase und Codes statt Klartext. Fehler in den Daten sollen dort gefunden werden, wo sie
entstehen, und Bereinigungen müssen nachvollziehbar sein. Der Export darf nur aus einer
einzigen, geprüften Schicht gespeist werden.

## Entscheid

Drei Schichten, je ein Verzeichnis unter `sql/`, Ausführung in dieser Reihenfolge:

- `raw` (`sql/raw`): 1:1-Kopie der heruntergeladenen Dateien. Keine Bereinigung, keine
  Umbenennung. Tabellen `raw_*`. Datenverträge (pointblank) prüfen hier die Lieferung.
- `staging` (`sql/staging`): Typisierung, deutsche Spaltennamen, LV95-Geometrie, dokumentierte
  Bereinigung (z. B. Messwerte ausserhalb plausibler Bereiche). Tabellen `stg_*`.
- `mart` (`sql/mart`): Anreicherung (Quartier, Schulnähe, Tempo, Wetter) und Aggregate für die
  Veröffentlichung. Tabellen `mart_*`. Nur Marts erreichen den Export.

Prüfungen (`sql/dq`) benennen im Header, welche Tabelle sie brauchen; sie hängen sich so an die
Schicht, in der der Fehler sichtbar wird.

## Konsequenzen

- Jeder Fehler ist einer Schicht zuordenbar: Lieferfehler (raw), Bereinigung (staging),
  Geschäftslogik (mart).
- Rohdaten bleiben unverändert und mit SHA-256 im Manifest belegt; Staging kann beliebig neu
  gebaut werden.
- Mehr Tabellen und Dateien als ein einziges Skript; dafür kleine, einzeln lintbare Schritte.
- Die Dateinamen-Präfixe (`01_`, `02_`, `10_`) bestimmen die Reihenfolge innerhalb der Schicht.
- Der Track-X-Mart (`10_trackx.sql`) liegt in der Mart-Schicht, wird aber nur gebaut, wenn die
  private Datei vorhanden ist (ADR 0004).
