# Severity ladder: tuning. Selection by validation Brier only; the test set is never an argument here.
# Protocol: elastic net = regular grid 30 (penalty x mixture); random forest and XGBoost = tune_race_anova
# over Latin-hypercube candidates.

tune_metrics <- function() {
  yardstick::metric_set(yardstick::brier_class, yardstick::mn_log_loss, yardstick::roc_auc)
}

tuning_grid <- function(id, wf, train, s) {
  if (id == "glmnet") {
    return(dials::grid_regular(dials::penalty(c(-6, -1)), dials::mixture(c(0, 1)),
                               levels = c(penalty = 10, mixture = 3)))
  }
  ps <- hardhat::extract_parameter_set_dials(wf)
  ps <- if (id == "rf") {
    stats::update(ps, mtry = dials::mtry(c(2L, length(sev_predictors()))), min_n = dials::min_n(c(5L, 150L)))
  } else {
    stats::update(ps,
      tree_depth = dials::tree_depth(c(2L, 8L)), learn_rate = dials::learn_rate(c(-2, -0.7)),
      min_n = dials::min_n(c(5L, 100L)), loss_reduction = dials::loss_reduction(c(-6, 1)),
      sample_size = dials::sample_prop(c(0.5, 1)), mtry = dials::mtry_prop(c(0.3, 1)))
  }
  n <- if (id == "rf") s$n_cand_rf else s$n_cand_xgb
  dials::grid_space_filling(ps, size = n, type = "latin_hypercube")
}

# tune_* (train) -> chosen parameters + candidate table. `train` and `resamples` are all it gets.
tune_model <- function(id, train, resamples, s) {
  assert_resamples_in_train(train, resamples)
  set.seed(s$seed)   # also fixes the Latin-hypercube candidates
  wf <- tuning_workflow(id, train, s)
  grid <- tuning_grid(id, wf, train, s)
  res <- if (id == "glmnet") {
    tune::tune_grid(wf, resamples, grid = grid, metrics = tune_metrics(), control = tune::control_grid())
  } else {
    finetune::tune_race_anova(wf, resamples, grid = grid, metrics = tune_metrics(),
                              control = finetune::control_race(burn_in = 3, verbose_elim = FALSE))
  }
  best <- tune::select_best(res, metric = "brier_class")
  m <- tune::collect_metrics(res)
  brier <- m[m$.metric == "brier_class", ]
  ll <- m[m$.metric == "mn_log_loss", ]
  tab <- data.frame(kandidat = brier$.config)
  for (p in tuning_columns) tab[[p]] <- if (p %in% names(brier)) as.numeric(brier[[p]]) else NA_real_
  tab$brier_cv <- brier$mean
  tab$log_loss_cv <- ll$mean[match(brier$.config, ll$.config)]
  tab$n_resamples <- brier$n
  tab$gewaehlt <- brier$.config == best$.config
  list(params = best, table = tab, val_brier = min(tab$brier_cv[tab$n_resamples == max(tab$n_resamples)]))
}

tuning_columns <- c("penalty", "mixture", "mtry", "min_n", "tree_depth", "learn_rate", "loss_reduction", "sample_size")
