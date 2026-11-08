# ADR 0005: Datenqualität als Freigabe-Gate

Status: angenommen, 2026-11-08

## Kontext

Amtliche Daten ändern sich ohne Ankündigung: 2023 schrumpfte ein Datensatz von 180 000 auf
55 000 Zeilen, Messreihen enthalten Sensorfehler (unplausible Messwerte), Codelisten wachsen.
Ein Bericht, der darauf stillschweigend aufsetzt, ist wertlos. Qualitätsprüfung darf deshalb
keine nachträgliche Dokumentation sein, sondern muss die Veröffentlichung steuern.

## Entscheid

Datenqualität ist eine Freigabebedingung, kein Bericht:

- Prüfungen kommen aus drei Quellen: Datenverträge (`dq/contracts/*.yml`, pointblank),
  SQL-Prüfungen (`sql/dq/*.sql` mit Metadaten im Header) und R-Historienprüfungen
  (Snapshot-Vergleich, Aktualität).
- Jede Prüfung hat eine Schwere: STOP (Veröffentlichung bricht ab) oder WARN (sichtbar,
  blockiert nicht), optional mit Toleranz in Prozent.
- `dq_gate()` bricht mit Fehler ab, sobald eine STOP-Prüfung verletzt ist; Modelle, Exporte und
  Site hängen im Target-Graph davon ab.
- Muster Erkennen, Reparieren, Verifizieren: erst Prüfung, die den Fehler findet (z. B. M02,
  Wertebereiche roh), dann dokumentierte Bereinigung in Staging, dann Prüfung auf dem
  bereinigten Stand (M05), die beweist, dass die Reparatur greift.
- Die Prüfungen selbst werden mit absichtlich kaputten Fixtures getestet.

## Konsequenzen

- Ein fehlerhafter Datenstand führt zu einem roten Lauf statt zu falschen Zahlen.
- Der Prüfkatalog ist Teil der Veröffentlichung (`export/dq`) und damit überprüfbar.
- Neue Prüfungen kosten eine SQL-Datei mit Header; Schwere und Toleranz sind eine
  inhaltliche Entscheidung und gehören ins Review.
- Zu strenge STOP-Regeln blockieren Läufe bei harmlosen Quellenänderungen; im Zweifel WARN.
- Siehe `docs/datenqualitaet.md` (Katalog, Anleitung) und ADR 0002 (Gate im Graph).
