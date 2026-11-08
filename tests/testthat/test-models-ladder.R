# End-to-end on a small synthetic table: both splits, all eight models, bootstrap, interpretation, export.
setup_ladder <- local({
  cache <- NULL
  function() {
    if (is.null(cache)) {
      d <- synthetic_accidents(per_year = 230, last_year = 2020)
      plan <- model_year_plan(2020, 2011)
      s <- tiny_settings()
      zeit <- run_ladder(d, plan, "zeitlich", s, interpret = TRUE)
      zufall <- run_ladder(d, plan, "zufaellig", s, only = zeit$best_tuned)
      cache <<- list(d = d, plan = plan, s = s, zeit = zeit, zufall = zufall,
                     bz = run_bootstrap(zeit, s), bf = run_bootstrap(zufall, s))
    }
    cache
  }
})

test_that("all models share rows, folds and bootstrap; probabilities are clipped and log-loss is finite", {
  x <- setup_ladder()
  expect_equal(colnames(x$zeit$probs), ladder_table()$modell)
  expect_equal(nrow(x$zeit$probs), nrow(x$zeit$test))                       # one common test set for all models
  expect_false(anyNA(x$zeit$probs))
  expect_true(all(x$zeit$probs >= sev_clip & x$zeit$probs <= 1 - sev_clip))
  expect_true(all(x$zeit$test$jahr %in% x$plan$test))
  expect_true(all(x$zeit$runtimes$sekunden >= 0))
  v <- x$bz$vergleich
  expect_true(all(is.finite(v$wert[v$metrik == "log_loss"])))
  expect_setequal(unique(v$modell), ladder_table()$modell)
  expect_setequal(unique(v$stufe), 1:8)
  expect_setequal(colnames(x$zufall$probs), ladder_table()$modell)
})

test_that("temporal test years only, regime subsets only in the random split, split labels set", {
  x <- setup_ladder()
  expect_setequal(unique(x$bz$vergleich$auswertung), c("alle", "ohne_parkier_tier"))
  expect_setequal(unique(x$bf$vergleich$auswertung), c("alle", "ohne_parkier_tier", "vor_2015", "ab_2015"))
  expect_setequal(unique(x$bz$vergleich$split), "zeitlich")
  expect_setequal(unique(x$bf$vergleich$split), "zufaellig")
  expect_setequal(unique(x$bz$vergleich$metrik), metric_names)
  expect_false(any(x$bz$differenzen$modell == sev_reference))
  expect_setequal(unique(x$bz$differenzen$referenz), c(sev_reference, sev_extra_reference))
  extra <- x$bz$differenzen[x$bz$differenzen$referenz == sev_extra_reference, ]
  expect_setequal(unique(extra$modell), c("Elastic Net", "GAM", "Random Forest", "XGBoost"))
})

tuned_first <- function(id, x) {
  m <- ladder_table()$modell[ladder_table()$id == id]
  g <- x$zeit$tuning[x$zeit$tuning$modell == m & x$zeit$tuning$gewaehlt, ][1, ]
  g[, intersect(tuning_columns, names(g)[!is.na(g)]), drop = FALSE]
}

predictors_of <- function(fit) {
  pre <- workflows::extract_preprocessor(fit$engine)
  if (inherits(pre, "recipe")) pre$var_info$variable[pre$var_info$role == "predictor"] else all.vars(pre)[-1]
}

test_that("no fitted model uses the year (recipe/formula inspection)", {
  x <- setup_ladder()
  expect_false(any(grepl("jahr", names(x$zeit$tuning))))
  sp <- make_split(x$d, "zeitlich", x$plan)
  for (id in c("lr_voll", "lr_ohne_typ", "glmnet", "rf", "xgb")) {
    fit <- fit_model(id, sp$train, if (id %in% c("glmnet", "rf", "xgb")) tuned_first(id, x) else NULL, x$s)
    nm <- predictors_of(fit)
    expect_false(any(grepl("jahr", nm)), info = id)
    expect_true("ab_2015" %in% nm, info = id)
  }
  expect_false(any(grepl("jahr", names(fit_model("gam", sp$train, NULL, x$s)$engine$model))))
})

test_that("descope step 1 keeps reference, baseline, rule, LR voll and only the best tuned model", {
  s <- tiny_settings(zufall = "reduced")
  ids <- ladder_rows("zufaellig", s, only = "Random Forest")$id
  expect_setequal(ids, c("basis", "regel", "lr_ohne_typ", "lr_voll", "rf"))
  expect_setequal(ladder_rows("zeitlich", s, only = "Random Forest")$id, ladder_table()$id)
  expect_false("gam" %in% ladder_rows("zeitlich", tiny_settings(gam = FALSE))$id)
})

test_that("tuning is deterministic for a fixed seed and selects by validation Brier", {
  d <- synthetic_accidents(per_year = 150, last_year = 2020)
  sp <- make_split(d, "zeitlich", model_year_plan(2020, 2011))
  s <- tiny_settings()
  for (id in c("glmnet", "rf")) {
    a <- tune_model(id, sp$train, sp$resamples, s)
    b <- tune_model(id, sp$train, sp$resamples, s)
    expect_equal(a$table, b$table, info = id)
    full <- a$table[a$table$n_resamples == max(a$table$n_resamples), ]
    expect_equal(a$table$kandidat[a$table$gewaehlt], full$kandidat[which.min(full$brier_cv)], info = id)
    expect_equal(sum(a$table$gewaehlt), 1)
  }
})

test_that("rule and baseline are train rates; LR ohne typ is the fixed reference", {
  d <- synthetic_accidents(per_year = 100, last_year = 2020)
  sp <- make_split(d, "zeitlich", model_year_plan(2020, 2011))
  b <- fit_basis(sp$train)
  expect_equal(unique(b$predict(sp$test)), mean(sp$train$personenschaden == "ja"))
  r <- fit_regel(sp$train)
  n_v <- pmin(rowSums(sp$train[, flag_cols]), 2)
  expect_equal(r$predict(sp$train[n_v == 2, ][1, ]), mean(sp$train$personenschaden[n_v == 2] == "ja"))
  expect_equal(r$predict(sp$train[n_v == 0, ][1, ]), mean(sp$train$personenschaden[n_v == 0] == "ja"))
})

test_that("interpretation tables are model-agnostic and complete", {
  x <- setup_ladder()
  imp <- x$zeit$importance
  expect_true(all(c("stunde", "mit_velo") %in% imp$merkmal))
  expect_true(all(imp$ki_low <= imp$wichtigkeit & imp$wichtigkeit <= imp$ki_high))
  expect_true(all(imp$n_wiederholungen == 2))
  expect_false("jahr" %in% imp$merkmal)
  expect_setequal(unique(x$zeit$calibration$modell), ladder_table()$modell)
  expect_true(all(x$zeit$calibration$n >= 10))
  eff <- x$zeit$effects
  expect_setequal(unique(eff$merkmal[eff$modell == "GAM"]),
                  c("stunde", "monat", "tempo_klasse", "mit_fussgaenger", "mit_velo", "mit_motorrad"))
  expect_true(all(eff$pdp > 0 & eff$pdp < 1))
  expect_true(all(x$zeit$odds_ratios$odds_ratio > 0))
  expect_false(any(grepl("typ", x$zeit$odds_ratios$term)))
})

test_that("export writes exactly the frozen schema", {
  x <- setup_ladder()
  out <- withr::local_tempdir()
  expected <- list(
    schwere_vergleich = c("modell", "stufe", "split", "auswertung", "metrik", "wert", "ki_low", "ki_high", "n"),
    schwere_differenzen = c("modell", "referenz", "split", "auswertung", "metrik", "differenz", "ki_low", "ki_high"),
    schwere_tuning = c("modell", "split", "kandidat", "penalty", "mixture", "mtry", "min_n", "tree_depth",
                       "learn_rate", "loss_reduction", "sample_size", "brier_cv", "log_loss_cv", "n_resamples",
                       "gewaehlt"),
    schwere_kalibrierung2 = c("modell", "split", "bin", "vorhergesagt", "beobachtet", "n"),
    schwere_wichtigkeit2 = c("modell", "split", "merkmal", "wichtigkeit", "ki_low", "ki_high", "n_wiederholungen"),
    schwere_effekte = c("modell", "split", "merkmal", "wert", "pdp", "n_zeilen"),
    schwere_odds_ratios2 = c("modell", "term", "odds_ratio", "ci_low", "ci_high", "p_value")
  )
  files <- export_ladder(x$zeit, x$zufall, x$bz, x$bf, x$s, x$plan, smoke_file = "none", out_dir = out)
  expect_setequal(basename(files), c(paste0(names(expected), ".csv"), "schwere_lauf.json"))
  for (nm in names(expected)) {
    got <- utils::read.csv(file.path(out, paste0(nm, ".csv")))
    expect_identical(names(got), expected[[nm]], info = nm)
    expect_gt(nrow(got), 0)
  }
  v <- utils::read.csv(file.path(out, "schwere_vergleich.csv"))
  expect_false(anyNA(v$wert))
  expect_true(all(is.finite(v$wert[v$metrik == "log_loss"])))
  lauf <- jsonlite::read_json(file.path(out, "schwere_lauf.json"))
  keys <- c("jahre", "split", "referenz", "zusatzreferenz", "basislinie", "bootstrap_n", "kandidaten", "baeume",
            "threads", "modelle_zufallssplit", "bestes_getuntes_modell", "descope", "laufzeit_sekunden",
            "budget_minuten", "smoke", "hyperparameter", "r_version")
  expect_setequal(names(lauf), keys)
  expect_equal(lauf$jahre$test, as.list(2018:2020))
  expect_equal(lauf$bootstrap_n, 30)
  expect_true(length(lauf$descope) >= 2)   # tiny settings reduce bootstrap and candidates, and it is recorded
})

test_that("descope steps are listed in plan order", {
  s <- model_settings()
  expect_length(descope_steps(s), 0)
  s2 <- model_settings(list(zufall = "reduced", n_boot = 500L, n_cand_rf = 10L, gam = FALSE))
  expect_match(descope_steps(s2), "^[1-4]:")
  expect_equal(substr(descope_steps(s2), 1, 1), as.character(1:4))
})
