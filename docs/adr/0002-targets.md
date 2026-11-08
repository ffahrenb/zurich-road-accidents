# ADR 0002: {targets} als Pipeline-Orchestrierung

Status: angenommen, 2026-11-08

## Kontext

Die Pipeline besteht aus Download, Warehouse-Bau, Datenqualitätsprüfung, Modellen, Export und
Site. Teile davon sind teuer (Download, Warehouse), Teile billig (Export). Änderungen an einer
SQL-Datei, an der Konfiguration oder an einem Datenschnappschuss sollen genau die betroffenen
Schritte neu auslösen. Die Abhängigkeiten müssen nachvollziehbar sein (Lineage), ohne ein
separates Orchestrierungssystem zu betreiben.

## Entscheid

`{targets}` mit `_targets.R` als einziger Pipeline-Definition. SQL-Dateien, DQ-Checks und
Verträge werden als `tar_files_input()` verfolgt; ändert sich eine Datei, läuft der Schritt
neu. Der Snapshot-Tag (`snapshot_date`) hat `cue = always`, so dass jeder Lauf einen neuen
Tagesstand zieht, aber denselben Tag wiederverwendet (idempotent, siehe `fetch_all()`).
Das Qualitäts-Gate (`dq_gate`) ist ein eigenes Target; alles danach hängt davon ab.

## Konsequenzen

- Inkrementelle, reproduzierbare Läufe; `tar_visnetwork()` liefert die Lineage-Grafik.
- Das Gate wirkt strukturell: Schlägt eine STOP-Prüfung an, werden Modelle, Exporte und Site
  nicht gebaut, weil ihre Voraussetzung fehlt (siehe ADR 0005).
- `_targets/` ist ein Cache (nicht versioniert, nicht im Image). In CI läuft immer ein
  Vollauf, der Cache ist dort nicht Teil der Aussage.
- R ist Pflicht für den Betrieb, die Fachlogik bleibt in SQL (ADR 0001, 0003).
- Targets mit Datei-Ausgabe (`format = "file"`) verfolgen die Datenbank per Hash; sehr
  grosse Dateien kosten dabei Hash-Zeit.
- Alternativen (Make, Snakemake, Airflow) verworfen: Make kennt keine R-Objekte,
  die anderen bringen Infrastruktur mit, die hier nicht gebraucht wird.
