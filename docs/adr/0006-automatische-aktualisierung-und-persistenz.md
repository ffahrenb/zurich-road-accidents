# ADR 0006: Automatische Aktualisierung und Persistenz

Status: angenommen, 2026-11-08

## Kontext

Die Pipeline läuft monatlich in GitHub Actions. Zwei Dinge verlangten bisher Handarbeit:

1. Der Auswertungszeitraum stand fest in `config/sources.yml` (`to: 2024`). Die Unfalldaten
   (eine Parquet-Datei mit allen Jahren) enthalten bald 2025; der Staging-Filter
   `accidentyear BETWEEN {{year_from}} AND {{year_to}}` hätte das Jahr stillschweigend verworfen.
   Meteo und Luft liegen dagegen als eine Ressource je Jahr vor und müssen für jedes Jahr
   existieren, sonst fehlen Stunden.
2. CI-Läufe starten bei null: `_targets/` und `data/raw/` werden nicht gespeichert, ein Lauf
   endete ohne Spur. `dq_verlauf.csv` und `snapshot_history.csv` wachsen nur, wenn ein Mensch die
   Ausgaben lokal erzeugt und committet. Die Historienprüfungen (DQ-S01/S02) vergleichen dann mit
   einem veralteten Stand.

## Entscheid

**Jahresbereich automatisch.** `years.to: auto` (Zahl bleibt möglich). Aufgelöst wird beim Ingest
(`R/years.R`) als das neueste Jahr, für das alle Eingänge vorliegen: Unfalldatei und lückenlose
Jahresressourcen in CKAN. Die Bevölkerung begrenzt den Bereich nicht; fehlt ihr Jahr, schreibt der
Mart den neuesten Stand fort und DQ-B03 warnt. Der Bereich ist Teil des Snapshots (`years.csv`,
Manifest-Spalten) und der Veröffentlichung (`export/dq/jahresbereich.csv`, DCAT-Zeitraum). Die
Website leitet Jahreszahlen aus `export/data/jahr.csv` ab.

Schutzregeln, als Prüfungen sichtbar gemacht:

- DQ-S03 (WARN): hat das neueste Unfalljahr weniger als 80 % des Vorjahres, ist es unvollständig und
  wird ausgelassen.
- DQ-S04 (STOP): der veröffentlichte Bereich darf gegenüber dem letzten Snapshot nie kleiner werden.
- DQ-S05 (WARN): nennt die Quelle, die den Bereich begrenzt.

**Persistenz aus CI.** Nach allen Gates lädt der Build `export/` als Artifact (mit `SHA256SUMS`)
hoch. Ein eigener Job `persist` (nur `schedule`/`workflow_dispatch` auf `main`, nach Build und
Deployment, als einziger mit `contents: write`) prüft das Artifact, ersetzt `export/` ausser
`export/trackx`, committet als `github-actions[bot]` und pusht, nur wenn sich `export/` geändert
hat und nichts ausserhalb. Die Logik steht in `tools/persist-export.sh` und ist offline getestet.

## Alternativen

- **Jahr von Hand erhöhen.** Fehleranfällig, genau der Fall, der zum Verlust von 2025 führte.
- **Bereich nur aus der Unfalldatei ableiten.** Würde ein Jahr ohne Wetterdaten aufnehmen;
  DQ-M01 (Vollständigkeit der Stundenreihe) würde Lücken melden, die Quartier- und Wetterseiten
  hätten ein halbes Bild.
- **Bevölkerung als Bedingung.** Die Stadt veröffentlicht sie oft später; der ganze Bereich würde
  für ein Detail der Quartier-Raten stehen bleiben. Fortschreiben mit sichtbarer Warnung ist ehrlicher
  als Stillstand.
- **Cache oder `_targets/` als Artifact.** Verfällt, ist nicht prüfbar, nicht lesbar. Das Repository
  ist das Archiv: die Ergebnisse sind klein (wenige MB), diffbar und öffentlich ohnehin.
- **Commit aus dem Build-Job.** Würde `contents: write` an den Job geben, der Pakete installiert
  und Repository-Code ausführt. Getrennter Job mit Prüfung der Artefakt-Bytes hält die Rechte klein.
- **Pull Request statt Direktcommit.** Wäre mit Branch-Schutz sauberer, bräuchte aber einen Token mit
  Schreibrecht auf Pull Requests und eine Freigabe pro Monat; das widerspricht „ohne Handarbeit".
  Offen, falls Branch-Schutz auf `main` eingeschaltet wird.

## Konsequenzen

- Neue Datenjahre erscheinen ohne Eingriff, sobald alle Quellen sie liefern. Ein unvollständiges
  Jahr, ein fehlendes Meteo-Jahr oder eine nachhinkende Bevölkerung verzögern oder warnen, sie
  blockieren nur, wenn sich der Bereich verkleinern würde.
- Ein STOP (auch DQ-S04) lässt Deploy und Persistenz aus: Die letzte veröffentlichte Version bleibt
  stehen. Eine bewusste Verkleinerung (Quelle zieht ein Jahr zurück) braucht einen Menschen: Zeile in
  `export/dq/jahresbereich.csv` anpassen und begründen.
- `main` bekommt monatlich einen Datencommit (`chore(data): refresh … [skip ci]`). Zeitstempel in
  Katalog, Berichten und Manifest ändern sich bei jedem Lauf, ein Commit entsteht also immer.
  Pushes mit dem Standard-`GITHUB_TOKEN` lösen keinen weiteren Lauf aus.
- Schlägt der Push fehl (Branch-Schutz, Rennen zweimal verloren), ist der Job rot und die Daten
  gehen nicht verloren: der nächste Lauf erzeugt sie neu und der Verlauf holt auf.
- `export/trackx` bleibt Byte für Byte, was committet ist; CI schreibt es nie.
- Nur auf GitHub prüfbar: die Rechte des `GITHUB_TOKEN` (Repository-Einstellung „Workflow
  permissions"), Branch-Schutz auf `main` und das Verhalten von Artifact-Upload und -Download
  in der Container-Umgebung.
- Siehe `docs/pipeline.md` (Abschnitt Automatisierung) und ADR 0005 (Gate).
