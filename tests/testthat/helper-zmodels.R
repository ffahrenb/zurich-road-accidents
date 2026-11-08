# Fixtures for the severity ladder tests: code under test plus a small synthetic accident table.
for (f in c("years.R", list.files(file.path(repo_root, "R"), "^models_.*\\.R$"), "export.R", "export_ladder.R")) {
  source(file.path(repo_root, "R", f), local = FALSE)
}

# Synthetic accidents 2011..last_year, raw mart columns; injury depends on vulnerable road users and type.
synthetic_accidents <- function(per_year = 260, last_year = 2020, seed = 7) {
  set.seed(seed)
  n <- per_year * (last_year - 2011 + 1)
  d <- data.frame(
    jahr = rep(2011:last_year, each = per_year), stunde = sample(0:23, n, TRUE), wochentag = sample(1:7, n, TRUE),
    monat = sample(1:12, n, TRUE),
    typ = sample(c("Parkierunfall", "Tierunfall", "Abbiegeunfall", "Auffahrunfall", "Fussgängerunfall"), n, TRUE),
    strassenart = sample(c("Hauptstrasse", "Nebenstrasse", "andere"), n, TRUE),
    tempo_klasse = sample(c("Tempo 30 oder tiefer", "Tempo 50", "unbekannt"), n, TRUE),
    mit_fussgaenger = runif(n) < 0.08, mit_velo = runif(n) < 0.15, mit_motorrad = runif(n) < 0.07,
    nahe_schule = runif(n) < 0.2, kreis_nr = sample(0:12, n, TRUE)
  )
  eta <- -1.6 + 2 * d$mit_velo + 2.5 * d$mit_fussgaenger + 1.5 * d$mit_motorrad - 2 * (d$typ == "Parkierunfall") +
    0.5 * (d$stunde >= 22) - 0.3 * (d$jahr >= 2015)
  d$personenschaden <- runif(n) < stats::plogis(eta)
  prepare_severity_data(d)
}

tiny_settings <- function(...) {
  model_settings(utils::modifyList(list(
    n_boot = 30L, n_cand_rf = 3L, n_cand_xgb = 3L, rf_trees = 30L, xgb_trees = 40L, xgb_stop = 5L,
    imp_reps = 2L, imp_rows = 300L, pdp_rows = 100L, threads = 2L
  ), list(...)))
}
