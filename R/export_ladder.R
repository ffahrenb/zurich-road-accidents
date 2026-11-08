# Export of the severity ladder.
# Schemas are frozen; tests/testthat/test-models-ladder.R lists them again, independently.
ladder_schema <- list(
  schwere_vergleich = c("modell", "stufe", "split", "auswertung", "metrik", "wert", "ki_low", "ki_high", "n"),
  schwere_differenzen = c("modell", "referenz", "split", "auswertung", "metrik", "differenz", "ki_low", "ki_high"),
  schwere_tuning = c("modell", "split", "kandidat", "penalty", "mixture", "mtry", "min_n", "tree_depth",
                     "learn_rate", "loss_reduction", "sample_size", "brier_cv", "log_loss_cv", "n_resamples",
                     "gewaehlt"),
  schwere_kalibrierung = c("modell", "split", "bin", "vorhergesagt", "beobachtet", "n"),
  schwere_wichtigkeit = c("modell", "split", "merkmal", "wichtigkeit", "ki_low", "ki_high", "n_wiederholungen"),
  schwere_effekte = c("modell", "split", "merkmal", "wert", "pdp", "n_zeilen"),
  schwere_odds_ratios = c("modell", "term", "odds_ratio", "ci_low", "ci_high", "p_value")
)

round_cols <- function(x, places = 4) {
  raw_penalty <- x$penalty
  num <- vapply(x, is.double, logical(1))
  x[num] <- lapply(x[num], round, places)
  # the elastic-net penalty grid spans 1e-10 .. 0.1: significant digits, not decimal places
  if ("penalty" %in% names(x)) x$penalty <- signif(raw_penalty, 3)
  x
}

# Descope steps in the order of the plan; each one taken is documented in schwere_lauf.json.
descope_steps <- function(s) {
  c(
    if (identical(s$zufall, "reduced")) "1: Zufallssplit nur fuer LR voll + bestes getuntes Modell",
    if (s$n_boot < 2000L) paste0("2: Bootstrap auf ", s$n_boot, " Ziehungen reduziert"),
    if (s$n_cand_rf < 20L || s$n_cand_xgb < 20L) "3: Racing-Kandidaten reduziert",
    if (!s$gam) "4: GAM gestrichen"
  )
}

runtime_by_model <- function(rt) {
  lapply(split(rt, rt$modell), function(g) {
    as.list(round(stats::setNames(g$sekunden, paste(g$split, g$phase, sep = "_")), 1))
  })
}

ladder_run_info <- function(zeit, zufall, boots, s, plan, smoke) {
  rt <- rbind(zeit$runtimes, zufall$runtimes)
  boot_sec <- vapply(boots, `[[`, numeric(1), "sec")
  chosen <- lapply(split(zeit$params, zeit$params$modell), function(g) {
    as.list(stats::setNames(signif(g$wert, 4), g$parameter))
  })
  list(
    jahre = plan,
    split = list(
      zeitlich = list(n_train = zeit$n_train, n_test = zeit$n_test),
      zufaellig = list(n_train = zufall$n_train, n_test = zufall$n_test)
    ),
    referenz = sev_reference, zusatzreferenz = sev_extra_reference, basislinie = sev_baseline, bootstrap_n = s$n_boot,
    kandidaten = list(random_forest = s$n_cand_rf, xgboost = s$n_cand_xgb, elastic_net_grid = 30L),
    baeume = list(random_forest = s$rf_trees, xgboost_max = s$xgb_trees, xgboost_runden_gewaehlt = zeit$rounds),
    threads = s$threads, modelle_zufallssplit = colnames(zufall$probs), bestes_getuntes_modell = zeit$best_tuned,
    descope = as.list(descope_steps(s)),
    laufzeit_sekunden = list(
      gesamt = round(sum(rt$sekunden) + sum(boot_sec), 1),
      bootstrap = stats::setNames(as.list(round(boot_sec, 1)), c("zeitlich", "zufaellig")),
      je_modell = runtime_by_model(rt)
    ),
    budget_minuten = list(lokal = s$budget_min_lokal, ci = s$budget_min_ci),
    smoke = smoke, hyperparameter = chosen, r_version = paste(R.version$major, R.version$minor, sep = ".")
  )
}

export_ladder <- function(zeit, zufall, boot_zeit, boot_zufall, s, plan, smoke_file = "config/modell_smoke.json",
                          out_dir = "export/modell") {
  smoke <- if (file.exists(smoke_file)) jsonlite::read_json(smoke_file) else NULL
  tables <- list(
    schwere_vergleich = rbind(boot_zeit$vergleich, boot_zufall$vergleich),
    schwere_differenzen = rbind(boot_zeit$differenzen, boot_zufall$differenzen),
    schwere_tuning = rbind(zeit$tuning, zufall$tuning),
    schwere_kalibrierung = rbind(zeit$calibration, zufall$calibration),
    schwere_wichtigkeit = cbind(split = zeit$kind, zeit$importance),
    schwere_effekte = cbind(split = zeit$kind, zeit$effects),
    schwere_odds_ratios = zeit$odds_ratios
  )
  tables$schwere_odds_ratios$p_value <- signif(tables$schwere_odds_ratios$p_value, 3)
  files <- vapply(names(ladder_schema), function(nm) {
    write_csv(round_cols(tables[[nm]][, ladder_schema[[nm]]], if (nm == "schwere_effekte") 5 else 4),
              file.path(out_dir, paste0(nm, ".csv")))
  }, character(1))
  lauf <- file.path(out_dir, "schwere_lauf.json")
  jsonlite::write_json(ladder_run_info(zeit, zufall, list(boot_zeit, boot_zufall), s, plan, smoke), lauf,
                       auto_unbox = TRUE, pretty = TRUE, digits = NA, null = "null")
  c(unname(files), lauf)
}
