# Severity ladder: fast metrics and the paired bootstrap.
# A bootstrap sample is expressed as integer case weights (how often each test row is drawn) on the
# fixed, once-sorted test set. All models see the SAME weights, no re-sorting per replicate, so 2000
# replicates stay cheap. Validated against yardstick (tests/testthat/test-models-metrics.R).

sev_clip <- 1e-6
metric_names <- c("roc_auc", "pr_auc", "brier", "log_loss", "brier_skill")

# Probabilities live in [1e-6, 1 - 1e-6]: finite log-loss for every model, incl. rule and baseline.
clip_prob <- function(p, eps = sev_clip) pmin(pmax(p, eps), 1 - eps)

# Everything that does not depend on the replicate: sort order, tie groups, per-row losses.
metric_prep <- function(p, y) {
  p <- clip_prob(p)
  o <- order(p)
  ps <- p[o]
  list(
    o = o, ys = y[o], ge = c(which(ps[-1] != ps[-length(ps)]), length(ps)),
    sq = (p - y)^2, ll = -(y * log(p) + (1 - y) * log(1 - p))
  )
}

# ROC-AUC (Mann-Whitney, ties count 0.5), PR-AUC (trapezoid incl. the (0, 1) start point, as yardstick),
# Brier and log-loss for case weights w (original row order). brier_skill is added by the caller.
weighted_metrics <- function(prep, w) {
  ws <- w[prep$o]
  cpos <- cumsum(ws * prep$ys)[prep$ge]
  cneg <- cumsum(ws * (1 - prep$ys))[prep$ge]
  n_pos <- cpos[length(cpos)]
  n_neg <- cneg[length(cneg)]
  pos_g <- diff(c(0, cpos))
  neg_g <- diff(c(0, cneg))
  auc <- sum(pos_g * (c(0, cneg[-length(cneg)]) + 0.5 * neg_g)) / (n_pos * n_neg)
  # PR curve: thresholds from high to low = groups in reverse order; groups without weight (not drawn / outside
  # the subset) are no thresholds of the resampled data, as in yardstick
  seen <- rev(pos_g + neg_g > 0)
  tp <- cumsum(rev(pos_g))[seen]
  fp <- cumsum(rev(neg_g))[seen]
  recall <- c(0, tp / n_pos)
  precision <- c(1, tp / (tp + fp))
  pr <- sum(diff(recall) * (precision[-1] + precision[-length(precision)]) / 2)
  sw <- sum(w)
  c(roc_auc = auc, pr_auc = pr, brier = sum(w * prep$sq) / sw, log_loss = sum(w * prep$ll) / sw)
}

# Bootstrap draw b as case weights; the seed depends on b only, so any core count gives the same draws.
bootstrap_counts <- function(n, b, seed) {
  set.seed(seed + b)
  tabulate(sample.int(n, n, replace = TRUE), nbins = n)
}

# All metrics for all models and subsets under ONE weight vector.
# preps: list per model; subsets: list of 0/1 numeric vectors; base: name of the baseline model.
metrics_for_weights <- function(preps, subsets, w, base) {
  out <- array(NA_real_, c(length(preps), length(subsets), length(metric_names)),
               dimnames = list(names(preps), names(subsets), metric_names))
  for (s in names(subsets)) {
    ws <- w * subsets[[s]]
    if (sum(ws) == 0) next
    for (m in names(preps)) out[m, s, 1:4] <- weighted_metrics(preps[[m]], ws)
    out[, s, "brier_skill"] <- 1 - out[, s, "brier"] / out[base, s, "brier"]
  }
  out
}

# probs: n x M matrix of probabilities (columns = models), y: 0/1, subsets: named logical list.
# Returns the point estimates (full test set) and B bootstrap replicates, both as model x subset x metric.
paired_bootstrap <- function(probs, y, subsets, base, n_boot = 2000L, seed = 2026L, cores = 1L) {
  preps <- lapply(stats::setNames(colnames(probs), colnames(probs)), function(m) metric_prep(probs[, m], y))
  subsets <- lapply(subsets, as.numeric)
  point <- metrics_for_weights(preps, subsets, rep(1, nrow(probs)), base)
  one <- function(b) metrics_for_weights(preps, subsets, bootstrap_counts(nrow(probs), b, seed), base)
  reps <- parallel::mclapply(seq_len(n_boot), one, mc.cores = cores)
  reps <- array(unlist(reps), c(dim(point), n_boot), dimnames = c(dimnames(point), list(NULL)))
  if (anyNA(point) || anyNA(reps)) stop("bootstrap produced undefined metrics", call. = FALSE)
  list(point = point, reps = reps, n_boot = n_boot, n = vapply(subsets, sum, numeric(1)))
}

ci95 <- function(x) stats::quantile(x, c(0.025, 0.975), na.rm = TRUE, names = FALSE)

# Tidy tables from a bootstrap result: metric table with CI and differences to the reference model (plus
# optional extra reference models, compared with the more complex ones only).
bootstrap_tables <- function(bt, split, reference, stufen, extra_refs = character()) {
  d <- dimnames(bt$point)
  grid <- expand.grid(modell = d[[1]], auswertung = d[[2]], metrik = d[[3]], stringsAsFactors = FALSE)
  at <- function(a, i) a[cbind(match(i$modell, d[[1]]), match(i$auswertung, d[[2]]), match(i$metrik, d[[3]]))]
  ci <- t(vapply(seq_len(nrow(grid)), function(r) {
    ci95(bt$reps[grid$modell[r], grid$auswertung[r], grid$metrik[r], ])
  }, numeric(2)))
  vergleich <- data.frame(
    modell = grid$modell, stufe = unname(stufen[grid$modell]), split = split, auswertung = grid$auswertung,
    metrik = grid$metrik, wert = at(bt$point, grid), ki_low = ci[, 1], ki_high = ci[, 2],
    n = unname(bt$n[grid$auswertung]), stringsAsFactors = FALSE
  )
  diff_for <- function(ref, models) {
    dg <- grid[grid$modell %in% models, ]
    dci <- t(vapply(seq_len(nrow(dg)), function(r) {
      ci95(bt$reps[dg$modell[r], dg$auswertung[r], dg$metrik[r], ] -
             bt$reps[ref, dg$auswertung[r], dg$metrik[r], ])
    }, numeric(2)))
    data.frame(
      modell = dg$modell, referenz = ref, split = split, auswertung = dg$auswertung, metrik = dg$metrik,
      differenz = at(bt$point, dg) - at(bt$point, transform(dg, modell = ref)), ki_low = dci[, 1], ki_high = dci[, 2],
      stringsAsFactors = FALSE
    )
  }
  # main reference: all other models. Extra references (fixed in advance): only the more complex models.
  diffs <- diff_for(reference, setdiff(d[[1]], reference))
  for (ref in extra_refs) diffs <- rbind(diffs, diff_for(ref, d[[1]][stufen[d[[1]]] > stufen[[ref]]]))
  list(vergleich = vergleich[!is.na(vergleich$wert), ], differenzen = diffs[!is.na(diffs$differenz), ])
}
