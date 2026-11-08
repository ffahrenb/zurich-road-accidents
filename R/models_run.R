# Severity ladder: orchestration. tune (train only) -> freeze -> fit -> evaluate (test).
# Settings come from config/modell.yml; every descope step taken there is written to schwere_lauf.json.

model_settings <- function(cfg = list()) {
  threads <- as.integer(Sys.getenv("ZH_THREADS", min(8L, parallel::detectCores())))
  defaults <- list(
    seed = sev_seed, threads = threads, n_boot = 2000L, n_cand_rf = 20L, n_cand_xgb = 20L, rf_trees = 500L,
    xgb_trees = 1000L, xgb_stop = 25L, gam = TRUE, zufall = "alle", imp_reps = 5L, imp_rows = 5000L,
    pdp_rows = 2000L, budget_min_lokal = 15, budget_min_ci = 30
  )
  utils::modifyList(defaults, cfg)
}

timed <- function(expr) {
  t0 <- proc.time()[["elapsed"]]
  value <- expr
  list(value = value, sec = proc.time()[["elapsed"]] - t0)
}

# Which ladder rows run for this split. The reference, baseline, rule and LR voll always run.
ladder_rows <- function(kind, s, only = NULL) {
  tl <- ladder_table()
  if (!s$gam) tl <- tl[tl$id != "gam", ]
  if (kind == "zufaellig" && identical(s$zufall, "reduced") && !is.null(only)) {
    tl <- tl[!tl$tuned & tl$id != "gam" | tl$modell %in% only, ]
  }
  tl
}

sample_rows <- function(d, n, seed) {
  set.seed(seed)
  d[sort(sample.int(nrow(d), min(n, nrow(d)))), ]
}

run_ladder <- function(d, plan, kind, s, only = NULL, interpret = FALSE) {
  sp <- make_split(d, kind, plan, s$seed)
  tl <- ladder_rows(kind, s, only)
  y <- as.integer(sp$test$personenschaden == "ja")
  out <- list(tuning = list(), params = list(), runtimes = list(), calibration = list(), importance = list(),
              effects = list(), odds_ratios = NULL, val_brier = c(), rounds = NA_integer_)
  probs <- matrix(NA_real_, nrow(sp$test), nrow(tl), dimnames = list(NULL, tl$modell))
  if (interpret) {
    imp_nd <- sample_rows(sp$test, s$imp_rows, s$seed)
    imp_y <- as.integer(imp_nd$personenschaden == "ja")
    shuffles <- permutation_shuffles(setdiff(sev_predictors(), character()), nrow(imp_nd), s$imp_reps, s$seed)
    pdp_nd <- sample_rows(sp$test, s$pdp_rows, s$seed + 1L)
  }
  for (i in seq_len(nrow(tl))) {
    id <- tl$id[i]
    m <- tl$modell[i]
    rt <- function(phase, sec) {
      out$runtimes[[length(out$runtimes) + 1L]] <<- data.frame(modell = m, split = kind, phase = phase, sekunden = sec)
    }
    params <- NULL
    if (tl$tuned[i]) {
      tm <- timed(tune_model(id, sp$train, sp$resamples, s))
      params <- tm$value$params
      rt("tuning", tm$sec)
      out$tuning[[m]] <- cbind(modell = m, split = kind, tm$value$table)
      pv <- unlist(params[setdiff(names(params), ".config")])
      out$params[[m]] <- data.frame(modell = m, split = kind, parameter = names(pv), wert = unname(pv))
      out$val_brier[m] <- tm$value$val_brier
    }
    ft <- timed(fit_model(id, sp$train, params, s))
    rt("fit", ft$sec)
    fit <- ft$value
    pr <- timed(clip_prob(fit$predict(sp$test)))
    rt("predict", pr$sec)
    probs[, m] <- pr$value
    if (id == "xgb") out$rounds <- xgb_rounds(fit)
    out$calibration[[m]] <- calibration_table(probs[, m], y, m, kind)
    if (interpret) {
      it <- timed({
        out$importance[[m]] <- permutation_importance(fit, imp_nd, imp_y, shuffles, m)
        out$effects[[m]] <- partial_dependence(fit, pdp_nd, m)
        if (id == "lr_ohne_typ") out$odds_ratios <- odds_ratio_table(fit, m)
      })
      rt("interpretation", it$sec)
    }
  }
  tuned <- names(out$val_brier)
  out$best_tuned <- if (length(tuned)) tuned[which.min(out$val_brier)] else NA_character_
  tables <- c("tuning", "params", "runtimes", "calibration", "importance", "effects")
  out[tables] <- lapply(out[tables], function(x) do.call(rbind, unname(x)))
  c(out, list(kind = kind, probs = probs, y = y, test = sp$test[, c(".row", "jahr", "parkier_tier")], ladder = tl,
              n_train = nrow(sp$train), n_test = nrow(sp$test)))
}

# Paired bootstrap for one split: identical resamples for all models, CI for metrics and for differences.
run_bootstrap <- function(ladder, s) {
  subsets <- eval_subsets(ladder$test, ladder$kind)
  bt <- timed(paired_bootstrap(ladder$probs, ladder$y, subsets, sev_baseline, s$n_boot, s$seed, s$threads))
  stufen <- stats::setNames(ladder$ladder$stufe, ladder$ladder$modell)
  tabs <- bootstrap_tables(bt$value, ladder$kind, sev_reference, stufen, sev_extra_reference)
  c(tabs, list(sec = bt$sec, n_boot = s$n_boot))
}
