# Severity ladder: interpretation, identical method for every model (calibration, permutation importance,
# partial dependence) plus odds ratios of the logistic reference model. Works on the test set of the
# temporal split AFTER all hyperparameters are frozen; nothing here feeds back into model choice.

calibration_table <- function(p, y, modell, split) {
  bin <- cut(p, breaks = seq(0, 1, 0.1), include.lowest = TRUE)
  g <- lapply(split(seq_along(p), bin), function(i) {
    if (length(i) < 10) return(NULL)
    data.frame(bin = as.character(bin[i[1]]), vorhergesagt = mean(p[i]), beobachtet = mean(y[i]), n = length(i))
  })
  out <- do.call(rbind, g)
  if (is.null(out)) return(NULL)
  cbind(modell = modell, split = split, out, stringsAsFactors = FALSE)
}

brier_of <- function(p, y) mean((clip_prob(p) - y)^2)

# Permutation importance: increase in Brier score when one raw feature is shuffled. Shuffles are drawn once
# per (feature, repetition) and reused for every model. CI = t interval over the repetitions (it reflects
# shuffling noise, not sampling noise of the test set).
permutation_shuffles <- function(features, n, reps, seed) {
  set.seed(seed)
  stats::setNames(lapply(features, function(f) replicate(reps, sample.int(n), simplify = FALSE)), features)
}

permutation_importance <- function(fit, nd, y, shuffles, modell) {
  base <- brier_of(fit$predict(nd), y)
  rows <- lapply(intersect(names(shuffles), fit$uses), function(f) {
    delta <- vapply(shuffles[[f]], function(ix) {
      nd[[f]] <- nd[[f]][ix]
      brier_of(fit$predict(nd), y) - base
    }, numeric(1))
    half <- stats::qt(0.975, length(delta) - 1) * stats::sd(delta) / sqrt(length(delta))
    data.frame(modell = modell, merkmal = f, wichtigkeit = mean(delta), ki_low = mean(delta) - half,
               ki_high = mean(delta) + half, n_wiederholungen = length(delta))
  })
  out <- do.call(rbind, rows)
  if (is.null(out)) return(NULL)
  out[order(-out$wichtigkeit), ]
}

# Partial dependence for the features the page shows, on a fixed sample of test rows.
pdp_grid <- function(nd) {
  list(stunde = 0:23, monat = 1:12, tempo_klasse = levels(nd$tempo_klasse),
       mit_fussgaenger = 0:1, mit_velo = 0:1, mit_motorrad = 0:1)
}

partial_dependence <- function(fit, nd, modell) {
  grids <- pdp_grid(nd)
  rows <- lapply(intersect(names(grids), fit$uses), function(f) {
    pdp <- vapply(grids[[f]], function(v) {
      nd[[f]] <- if (is.factor(nd[[f]])) factor(v, levels = levels(nd[[f]])) else v
      mean(clip_prob(fit$predict(nd)))
    }, numeric(1))
    data.frame(modell = modell, merkmal = f, wert = as.character(grids[[f]]), pdp = pdp, n_zeilen = nrow(nd))
  })
  do.call(rbind, rows)
}

# Odds ratios of the logistic model without accident type. parsnip models the SECOND factor level ("nein"),
# so the sign is flipped: ORs describe "Personenschaden = ja". Wald intervals.
odds_ratio_table <- function(fit, modell) {
  td <- broom::tidy(workflows::extract_fit_engine(fit$engine))
  z <- stats::qnorm(0.975)
  td <- td[td$term != "(Intercept)", ]
  data.frame(
    modell = modell, term = td$term, odds_ratio = exp(-td$estimate),
    ci_low = exp(-td$estimate - z * td$std.error), ci_high = exp(-td$estimate + z * td$std.error),
    p_value = td$p.value, stringsAsFactors = FALSE
  )
}
