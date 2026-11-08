# ADR 0004: Zwei Datenpfade und Datenschutz

Status: angenommen, 2026-11-08

## Kontext

Die offenen Unfalldaten (ASTRA / Stadt Zürich) enthalten Jahr, Monat, Wochentag und Stunde,
aber kein Datum. Für das CAS-Projekt 2023 hat die Stadt Zürich die exakten Unfallzeitpunkte
zur Verfügung gestellt. Diese Datei ist nicht öffentlich. Mit ihr lässt sich der Einfluss
des Wetters stündlich statt monatlich schätzen. Werden daraus aber Zeilen, Datumsschlüssel
oder stündliche Wetterwerte veröffentlicht, kann man jede öffentliche Unfallzeile über
Jahr/Monat/Wochentag/Stunde einem exakten Datum zuordnen (Re-Identifikation).

## Entscheid

Zwei Datenpfade:

- Track A (öffentlich): nur offene Quellen, vollständig in CI reproduzierbar.
- Track X (privat): exakte Zeitpunkte, nur lokal über `ZH_PRIVATE_ACCIDENTS`. Die Datei liegt
  nie im Repository, nie im Image, nie in CI.

Veröffentlichungsregeln (F1): keine Track-X-Zeilendaten; keine Datumsschlüssel (Tag, Woche,
Datum-Stunde); keine rohen Stundenwetterwerte; nur grobe Klassen (Regen x Temperatur) mit
mindestens 10 Fällen und 10 Stunden je Zelle; Modelle nur als Koeffizienten.
Entscheid vom 2026-11-08: Es werden ausschliesslich Modellergebnisse veröffentlicht
(`export/trackx/wetter_effekt.csv`, `wetter_klassen.csv`, `wetter_modell.json`).

## Konsequenzen

- Die Regeln sind als Tests durchgesetzt (`tests/testthat/test-privacy.R`, inkl. Join-Angriff)
  und als Pre-Commit-Hook; Details in `docs/datenschutz.md`.
- Track-X-Ergebnisse werden lokal erzeugt und committet; CI läuft ohne private Daten und darf
  `export/trackx` nicht verändern.
- Ergebnisse von Track X sind für Dritte nicht nachrechenbar; Methode und Aggregate sind
  dokumentiert, die Eingangsdatei bleibt bei der Stadt Zürich.
- Wer neue Track-X-Ausgaben ergänzt, muss die Allowlist und den Privacy-Test bewusst erweitern.
