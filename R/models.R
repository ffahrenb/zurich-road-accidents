# Statistical models. Inputs come from marts; outputs are small tidy tables.
# Model objects never leave the pipeline (they would carry the training data).

temp_bin <- function(t) {
  cut(t, breaks = c(-Inf, 0, 5, 10, 15, 20, 25, Inf),
      labels = c("< 0", "0–5", "5–10", "10–15", "15–20", "20–25", "≥ 25"), right = FALSE)
}

# Track X: does rain change the number of accidents in the same hour?
# Negative binomial regression on the complete hourly series 2011-2021,
# controlling for hour of day x weekend, month and year (trend, recording change).
fit_weather <- function(db_path) {
  con <- db_connect(db_path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  if (!"mart_x_stunden" %in% DBI::dbListTables(con)) return(NULL)
  d <- DBI::dbGetQuery(con, "
    SELECT unfaelle, mit_personenschaden, mit_velo, regen_min, temperatur_c,
           hour(ts_lokal) AS stunde, isodow(ts_lokal) AS wochentag,
           month(ts_lokal) AS monat, year(ts_lokal) AS jahr
    FROM mart_x_stunden
    WHERE regen_min IS NOT NULL AND temperatur_c IS NOT NULL")
  d$regen <- factor(ifelse(d$regen_min > 0, "Regen", "trocken"), levels = c("trocken", "Regen"))
  d$temperatur <- stats::relevel(temp_bin(d$temperatur_c), ref = "10–15")
  d$tagesstunde <- interaction(d$stunde, d$wochentag >= 6)
  d$monat <- factor(d$monat); d$jahr <- factor(d$jahr)

  outcomes <- c(
    unfaelle = "Alle Unfälle", mit_personenschaden = "Unfälle mit Personenschaden",
    mit_velo = "Unfälle mit Velo"
  )
  irr <- do.call(rbind, lapply(names(outcomes), function(y) {
    f <- stats::as.formula(paste(y, "~ regen + temperatur + tagesstunde + monat + jahr"))
    m <- MASS::glm.nb(f, data = d)
    # Wald intervals: profile-likelihood CIs for ~80 coefficients take minutes.
    td <- broom::tidy(m)
    td <- td[grepl("^(regen|temperatur)", td$term), ]
    z <- stats::qnorm(0.975)
    data.frame(
      zielgroesse = outcomes[[y]], term = td$term,
      irr = round(exp(td$estimate), 3),
      ci_low = round(exp(td$estimate - z * td$std.error), 3),
      ci_high = round(exp(td$estimate + z * td$std.error), 3),
      p_value = signif(td$p.value, 3), n_stunden = stats::nobs(m)
    )
  }))
  irr$merkmal <- ifelse(grepl("^regen", irr$term), "Regen in der Stunde",
                        paste("Temperatur", sub("^temperatur", "", irr$term), "°C"))

  # Descriptive bins: accidents per hour by rain x temperature (no date keys).
  bins <- stats::aggregate(
    cbind(unfaelle, mit_personenschaden, stunden = 1) ~ regen + temperatur,
    data = d, FUN = sum
  )
  bins$unfaelle_pro_stunde <- round(bins$unfaelle / bins$stunden, 3)
  list(irr = irr, bins = bins, n_hours = nrow(d), period = range(as.integer(as.character(d$jahr))))
}

# Track P: which circumstances go with injury (vs. property damage only)?
# Split first, then cross-validate on training data only; test set touched once.
fit_severity <- function(db_path, seed = 2026) {
  con <- db_connect(db_path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  d <- DBI::dbGetQuery(con, "
    SELECT personenschaden, stunde, wochentag, monat, jahr, typ, strassenart,
           mit_fussgaenger, mit_velo, mit_motorrad, tempo_klasse, nahe_schule,
           coalesce(kreis_nr, 0) AS kreis_nr
    FROM mart_unfaelle")
  d$personenschaden <- factor(ifelse(d$personenschaden, "ja", "nein"), levels = c("ja", "nein"))
  for (v in c("typ", "strassenart", "tempo_klasse", "kreis_nr", "wochentag")) d[[v]] <- factor(d[[v]])
  for (v in c("mit_fussgaenger", "mit_velo", "mit_motorrad", "nahe_schule")) d[[v]] <- as.integer(d[[v]])
  d$nacht <- as.integer(d$stunde < 6 | d$stunde >= 22)

  set.seed(seed)
  split <- rsample::initial_split(d, prop = 0.8, strata = personenschaden)
  train <- rsample::training(split); test <- rsample::testing(split)
  folds <- rsample::vfold_cv(train, v = 5, strata = personenschaden)
  rec <- recipes::recipe(personenschaden ~ ., data = train) |>
    recipes::step_dummy(recipes::all_nominal_predictors()) |>
    recipes::step_zv(recipes::all_predictors())

  specs <- list(
    "Logistische Regression" = parsnip::logistic_reg() |> parsnip::set_engine("glm"),
    "Random Forest" = parsnip::rand_forest(trees = 400, min_n = 20) |>
      parsnip::set_engine("ranger", seed = seed) |>
      parsnip::set_mode("classification")
  )
  metrics <- yardstick::metric_set(yardstick::roc_auc, yardstick::pr_auc, yardstick::brier_class)
  res <- lapply(names(specs), function(nm) {
    wf <- workflows::workflow(rec, specs[[nm]])
    cv <- tune::fit_resamples(wf, folds, metrics = metrics)
    cvm <- tune::collect_metrics(cv)
    # Permutation importance is costly: compute it on the final fit only, not in every CV fold.
    if (nm == "Random Forest") {
      wf <- workflows::workflow(rec, parsnip::set_engine(specs[[nm]], "ranger", importance = "permutation", seed = seed))
    }
    fit <- parsnip::fit(wf, train)
    pred <- stats::predict(fit, test, type = "prob")
    pred$truth <- test$personenschaden
    tm <- metrics(pred, truth, .pred_ja)
    list(fit = fit, pred = pred,
         metrics = data.frame(modell = nm, metrik = tm$.metric, test = round(tm$.estimate, 3),
                              cv_mittel = round(cvm$mean[match(tm$.metric, cvm$.metric)], 3),
                              cv_se = round(cvm$std_err[match(tm$.metric, cvm$.metric)], 4)))
  })
  names(res) <- names(specs)
  prev <- mean(test$personenschaden == "ja")
  baseline <- data.frame(modell = "Basislinie (immer Anteil)", metrik = c("roc_auc", "pr_auc", "brier_class"),
                         test = round(c(0.5, prev, prev * (1 - prev)), 3), cv_mittel = NA, cv_se = NA)
  metr <- rbind(baseline, do.call(rbind, lapply(res, `[[`, "metrics")))

  # Calibration of the random forest on the test set (deciles).
  p <- res[["Random Forest"]]$pred
  p$bin <- cut(p$.pred_ja, breaks = seq(0, 1, 0.1), include.lowest = TRUE)
  calib <- do.call(rbind, lapply(split(p, p$bin), function(g) {
    if (!nrow(g)) return(NULL)
    data.frame(bin = as.character(g$bin[1]), vorhergesagt = round(mean(g$.pred_ja), 3),
               beobachtet = round(mean(g$truth == "ja"), 3), n = nrow(g))
  }))
  calib <- calib[calib$n >= 10, ]

  # Odds ratios from the logistic model (interpretable effects).
  lr <- workflows::extract_fit_engine(res[["Logistische Regression"]]$fit)
  or <- broom::tidy(lr)  # Wald intervals (profile likelihood is slow on 50k rows)
  z <- stats::qnorm(0.975)
  # parsnip models the SECOND factor level ("nein"); flip the sign so ORs describe "Personenschaden = ja".
  or$odds_ratio <- exp(-or$estimate)
  or$ci_low <- exp(-or$estimate - z * or$std.error)
  or$ci_high <- exp(-or$estimate + z * or$std.error)
  or <- or[or$term != "(Intercept)", c("term", "odds_ratio", "ci_low", "ci_high", "p.value")]
  names(or) <- c("term", "odds_ratio", "ci_low", "ci_high", "p_value")
  or[, 2:4] <- round(or[, 2:4], 3); or$p_value <- signif(or$p_value, 3)

  # Permutation importance of the random forest.
  rf <- workflows::extract_fit_engine(res[["Random Forest"]]$fit)
  imp <- data.frame(merkmal = names(rf$variable.importance), wichtigkeit = round(unname(rf$variable.importance), 5))
  imp <- imp[order(-imp$wichtigkeit), ]

  list(metrics = metr, calibration = calib, odds_ratios = or, importance = imp,
       n_train = nrow(train), n_test = nrow(test), prevalence = round(prev, 3))
}
