truth_factor <- function(y) factor(ifelse(y == 1, "ja", "nein"), levels = c("ja", "nein"))

yardstick_metrics <- function(p, y, w = NULL) {
  d <- data.frame(truth = truth_factor(y), p = p)
  c(roc_auc = yardstick::roc_auc(d, truth, p)$.estimate,
    avg_precision = yardstick::average_precision(d, truth, p)$.estimate,
    brier = yardstick::brier_class(d, truth, p)$.estimate, log_loss = yardstick::mn_log_loss(d, truth, p)$.estimate)
}

test_that("fast metrics equal yardstick (continuous scores, tol 1e-9)", {
  set.seed(1)
  y <- rbinom(3000, 1, 0.3)
  p <- clip_prob(stats::plogis(rnorm(3000) + 1.5 * (y - 0.3)))
  got <- weighted_metrics(metric_prep(p, y), rep(1, length(y)))
  expect_equal(got, yardstick_metrics(p, y), tolerance = 1e-9)
})

test_that("fast metrics equal yardstick with heavy ties and extreme probabilities", {
  set.seed(2)
  y <- rbinom(4000, 1, 0.25)
  p <- round(stats::plogis(rnorm(4000) + 2 * (y - 0.25)), 1)   # 0.0 / 1.0 appear -> clipped
  expect_true(any(p == 0) || any(p == 1))
  got <- weighted_metrics(metric_prep(p, y), rep(1, length(y)))
  expect_equal(got, yardstick_metrics(clip_prob(p), y), tolerance = 1e-9)
  expect_true(all(is.finite(got)))
  # constant score (baseline model): AUC 0.5, average precision = prevalence
  const <- weighted_metrics(metric_prep(rep(0.25, 4000), y), rep(1, 4000))
  expect_equal(const[["roc_auc"]], 0.5)
  expect_equal(const[["avg_precision"]], mean(y), tolerance = 1e-9)
  expect_equal(const, yardstick_metrics(rep(0.25, 4000), y), tolerance = 1e-9)
})

test_that("a weighted replicate equals yardstick on the materialised bootstrap sample", {
  set.seed(3)
  y <- rbinom(2000, 1, 0.3)
  p <- round(clip_prob(stats::plogis(rnorm(2000) + 1.2 * (y - 0.3))), 2)
  for (b in 1:3) {
    w <- bootstrap_counts(length(y), b, seed = 11L)
    idx <- rep(seq_along(y), w)
    expect_equal(weighted_metrics(metric_prep(p, y), w), yardstick_metrics(p[idx], y[idx]), tolerance = 1e-9)
  }
})

test_that("replicates with undrawn rows (continuous scores) and subsets still equal yardstick", {
  set.seed(6)
  y <- rbinom(800, 1, 0.3)
  p <- clip_prob(stats::plogis(rnorm(800) + 1.5 * (y - 0.3)))   # all distinct: top-scored rows are often undrawn
  keep <- seq_along(y) %% 4 != 0
  top <- which.max(p)
  for (b in 1:10) {
    w <- bootstrap_counts(length(y), b, seed = 3L) * keep
    w[top] <- 0                                                    # force the highest score out of the sample
    idx <- rep(seq_along(y), w)
    got <- weighted_metrics(metric_prep(p, y), w)
    expect_false(anyNA(got))
    expect_equal(got, yardstick_metrics(p[idx], y[idx]), tolerance = 1e-9)
  }
})

test_that("bootstrap draws are deterministic and identical for every model", {
  expect_identical(bootstrap_counts(500, 7, 2026L), bootstrap_counts(500, 7, 2026L))
  expect_false(identical(bootstrap_counts(500, 7, 2026L), bootstrap_counts(500, 8, 2026L)))
  expect_equal(sum(bootstrap_counts(500, 7, 2026L)), 500)
  set.seed(4)
  y <- rbinom(600, 1, 0.3)
  a <- clip_prob(stats::plogis(rnorm(600) + y))
  probs <- cbind(Basislinie = rep(mean(y), 600), A = a, B = a, C = rev(a))
  bt <- paired_bootstrap(probs, y, list(alle = rep(TRUE, 600)), "Basislinie", n_boot = 40L, seed = 5L, cores = 1L)
  # identical resamples: identical models give identical replicates, in any column order
  expect_identical(bt$reps["A", "alle", , ], bt$reps["B", "alle", , ])
  bt2 <- paired_bootstrap(probs[, c("C", "B", "A", "Basislinie")], y, list(alle = rep(TRUE, 600)), "Basislinie",
                          n_boot = 40L, seed = 5L, cores = 2L)
  expect_identical(bt$reps["A", "alle", , ], bt2$reps["A", "alle", , ])
  # a model against itself: difference CI is exactly zero
  tabs <- bootstrap_tables(bt, "zeitlich", "A", c(Basislinie = 1, A = 2, B = 3, C = 4))
  d <- tabs$differenzen
  expect_true(all(d$ki_low[d$modell == "B"] == 0 & d$ki_high[d$modell == "B"] == 0))
  expect_false(any(d$modell == "A"))
})

test_that("bootstrap CI brackets the point estimate and brier_skill of the baseline is 0", {
  set.seed(5)
  y <- rbinom(1500, 1, 0.3)
  probs <- cbind(Basislinie = rep(mean(y), 1500), M = clip_prob(stats::plogis(rnorm(1500) + 1.5 * y - 0.5)))
  bt <- paired_bootstrap(probs, y, list(alle = rep(TRUE, 1500), teil = seq_len(1500) %% 3 == 0), "Basislinie",
                         n_boot = 200L, seed = 1L)
  v <- bootstrap_tables(bt, "zeitlich", "Basislinie", c(Basislinie = 1, M = 2))$vergleich
  expect_true(all(v$ki_low <= v$wert + 1e-9 & v$wert <= v$ki_high + 1e-9))
  expect_true(all(v$wert[v$modell == "Basislinie" & v$metrik == "brier_skill"] == 0))
  expect_equal(v$n[v$auswertung == "teil"][1], 500)
})
