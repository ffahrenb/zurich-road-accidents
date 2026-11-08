# ADR 0007: Protokoll für den Modellvergleich (Schwere)

Status: angenommen, 2026-11-08

## Kontext

Die Seite «Schwere» fragt, ob ein Unfall Personenschaden hatte. Die erste Fassung verglich zwei
Modelle (logistische Regression, Random Forest ohne Abstimmung) auf einem Zufallssplit. Das hatte
vier Schwächen:

1. Der Zufallssplit mischt Jahre. Seit 2015 werden mehr reine Sachschaden-Unfälle erfasst, der Anteil
   mit Personenschaden fiel von 31.9 % auf 23.9 %. Der Test prüfte «bekannte Jahre nachzeichnen»,
   nicht «neue Jahre».
2. Kein Mass für Unsicherheit: 0.914 gegen 0.923 AUC liess sich nicht als echt oder Zufall lesen.
3. Kein fairer Algorithmenvergleich ohne Abstimmung, und keine Stufen von einfach nach komplex: Es
   fehlte die Antwort, wie viel Komplexität gegenüber einer simplen Regel bringt.
4. Interpretation (Kalibrierung, Wichtigkeit) nur für ein Modell.

## Entscheid

**Acht Modelle, eine Leiter:** (1) Basislinie (Trainings-Anteil), (2) Regel (Rate je Anzahl beteiligter
ungeschützter Gruppen), (3) logistische Regression ohne Unfalltyp, (4) logistische Regression voll,
(5) Elastic Net, (6) GAM, (7) Random Forest, (8) XGBoost. Alle sehen dieselben Trainings- und
Testzeilen, dieselben Folds und dieselben Bootstrap-Ziehungen. Wahrscheinlichkeiten sind auf
[1e-6, 1-1e-6] begrenzt, damit der Log-Loss für Regel und Basislinie endlich bleibt.

**Zeitlicher Test als Hauptauswertung.** Sei E das letzte Jahr des automatischen Bereichs (nur
vollständige Jahre, ADR 0006). Test = E-2 bis E, Validierungsjahre = E-6 bis E-3 (Rolling Origin,
wachsendes Fenster), Training final = Beginn bis E-3. Tuning und Auswahl sehen nur Trainingsjahre
(`tune → finalize → evaluate`), die Testzeilen werden erst nach dem Einfrieren der Hyperparameter
angefasst; ein Test prüft, dass Tuning-Funktionen keine Testzeilen erhalten. Der Zufallssplit läuft
als Kontrolle mit.

**Festes Referenzmodell vorab.** Differenzen beziehen sich auf «LR ohne Unfalltyp», zusätzlich auf
«LR voll» für die komplexeren Stufen. Keine testbasierte Auswahl des Vergleichsmassstabs. «Bestes
getuntes Modell» (für den Zufallssplit) bestimmt der Validierungs-Brier-Score, nie der Test.

**Gepaarter Bootstrap.** Intervalle und Differenzen kommen aus denselben Neuziehungen der
Testunfälle für alle Modelle (Zählgewichte auf dem einmal sortierten Testset, Seed hängt nur vom
Ziehungsindex ab). Die Metriken sind vektorisiert (AUC rangbasiert, Average Precision über sortierte
Kumulativsummen, Brier und Log-Loss als Mittel) und gegen yardstick auf 1e-9 getestet. Primäre
Kennzahl: Brier-Skill (1 - Brier/Brier der Basislinie); ROC-AUC, Average Precision und Log-Loss
sind sekundär. Die PR-Kennzahl ist Average Precision (Stufensumme, `yardstick::average_precision`),
nicht die Trapezfläche `pr_auc`: Bei konstantem Score ergibt sie den Anteil der Positiven, die
Trapezregel dagegen 0.625.

**`ab_2015` statt `jahr`.** Kein Modell erhält Jahr oder Trend, nur den Regime-Schalter `ab_2015`.
So extrapoliert keines über das letzte Trainingsjahr hinaus. Die Auswertung nach Regime (bis 2014 /
ab 2015) gibt es deshalb nur im Zufallssplit und ist dort gekennzeichnet; der Unterschied zwischen
zeitlichem und zufälligem Test ist Drift und andere Testmenge zugleich.

**Interpretation für alle Modelle gleich.** Kalibrierung (Zehnerbereiche, n ≥ 10),
Permutationswichtigkeit (Anstieg des Brier-Scores, Intervall über Wiederholungen), Partial
Dependence; Chancenverhältnisse nur aus der Regression ohne Unfalltyp, weil Unfalltyp und
«Fussgänger:in beteiligt» überlappen.

**Budget und Abstriche.** Alle Modell-Targets lokal (8 Threads) höchstens 15 Minuten, in CI
(4 vCPU) höchstens 30. Ein Smoke-Lauf misst Tuning und Bootstrap getrennt
(`config/modell_smoke.json`). Abstriche in dieser Reihenfolge, jeder sichtbar in
`export/modell/schwere_lauf.json` und auf der Seite: (1) Zufallssplit nur für LR voll und das beste
getunte Modell, (2) Bootstrap 2'000 auf 500, (3) Racing-Kandidaten 20 auf 10, (4) GAM streichen.
Stand heute sind (1) bis (3) genommen; der Volllauf dauert rund 10 Minuten lokal.
Einstellungen: `config/modell.yml`.

## Alternativen

- **Zufallssplit als Hauptauswertung.** Einfach, beantwortet aber die falsche Frage (siehe Kontext).
- **`jahr` als numerisches Merkmal.** Bäume extrapolieren nicht, lineare Modelle schon; der
  Vergleich wäre zwischen den Familien verzerrt.
- **Referenz = bestes Modell auf dem Test.** Selektionsfehler: Die Differenz zum Sieger wäre zu klein.
- **PR-Fläche (yardstick `pr_auc`).** Die Trapezregel ergibt für konstante Scores nicht den Anteil
  der Positiven und überschätzt ihn.
- **Bootstrap mit 2'000 Ziehungen und 20 Kandidaten.** Sauberer, sprengt aber das Laufzeitbudget in CI.

## Konsequenzen

- Die Seite zeigt Intervalle für alle Aussagen über Unterschiede; ein Unterschied gilt nur als echt,
  wenn die Null ausserhalb liegt. Das Intervall misst das Rauschen der Testunfälle, nicht die
  Unsicherheit künftiger Jahre und nicht die Abhängigkeit von Unfällen am selben Ort oder Tag.
- Das Wichtigkeits-Intervall misst das Rauschen des Durchmischens, nicht das der Testmenge.
- Mit jedem neuen Datenjahr verschiebt sich das Testfenster; Kennzahlen ändern sich ohne Eingriff.
  Ist der Bereich kürzer als 4 Validierungs- plus 3 Testjahre, bricht der Lauf ab.
- Die Abstriche sind kein Defekt, aber Teil der Aussage: Mehr Kandidaten könnten die Bäume noch
  etwas verbessern.
- Siehe `docs/pipeline.md` (Abschnitt Modelle), `R/models_*.R`, ADR 0006 (Jahresbereich).
