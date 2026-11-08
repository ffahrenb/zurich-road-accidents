# Smoke run of the severity ladder on a fraction of the data, for the budget check before a full run.
# Run via tools/model-smoke.sh (wraps /usr/bin/time -v).
# Usage: Rscript tools/model_smoke.R <phase> <fraction> <out.json>
#   phase tuning:    tuning + fit + interpretation of both splits on <fraction> of all rows
#   phase bootstrap: paired bootstrap with <fraction> of the draws on a full-size test set (synthetic scores)
args <- commandArgs(trailingOnly = TRUE)
phase <- args[1]
frac <- as.numeric(args[2])
for (f in list.files("R", "\\.R$", full.names = TRUE)) source(f)
s <- model_settings(yaml::read_yaml("config/modell.yml"))
t0 <- proc.time()[["elapsed"]]
if (phase == "tuning") {
  d <- load_severity_data("data/warehouse.duckdb")
  plan <- model_year_plan(max(d$jahr), min(d$jahr))
  set.seed(s$seed)
  d <- d[sort(sample.int(nrow(d), round(nrow(d) * frac))), ]
  z <- run_ladder(d, plan, "zeitlich", s, interpret = TRUE)
  r <- run_ladder(d, plan, "zufaellig", s, only = z$best_tuned)
  n <- c(train = z$n_train, test = z$n_test)
  rt <- rbind(z$runtimes, r$runtimes)
} else {
  n_test <- 16000L
  set.seed(1)
  y <- rbinom(n_test, 1, 0.25)
  score <- function(i) clip_prob(stats::plogis(stats::qlogis(0.25) + 0.3 * i * (y - 0.25) + stats::rnorm(n_test)))
  probs <- vapply(1:8, score, numeric(n_test))
  colnames(probs) <- ladder_table()$modell
  sub <- list(alle = rep(TRUE, n_test), ohne = stats::runif(n_test) > 0.2,
              vor = stats::runif(n_test) > 0.5, ab = stats::runif(n_test) > 0.5)
  for (i in 1:2) paired_bootstrap(probs, y, sub, sev_baseline, round(s$n_boot * frac), s$seed, s$threads)
  n <- c(test = n_test)
  rt <- NULL
}
jsonlite::write_json(list(phase = phase, fraction = frac, sekunden = proc.time()[["elapsed"]] - t0,
                          threads = s$threads, n = as.list(n), laufzeit = rt), args[3], auto_unbox = TRUE)
