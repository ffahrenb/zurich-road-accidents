# Severity ladder: the eight models. Every fit returns list(predict = function(newdata) -> P(injury),
# uses = raw predictors, engine = fitted object or NULL). Probabilities are clipped by the caller.

ladder_table <- function() {
  data.frame(
    id = c("basis", "regel", "lr_ohne_typ", "lr_voll", "glmnet", "gam", "rf", "xgb"),
    modell = c("Basislinie", "Regel (verletzliche Gruppen)", "LR ohne Unfalltyp", "LR voll", "Elastic Net",
               "GAM", "Random Forest", "XGBoost"),
    stufe = 1:8,
    tuned = c(FALSE, FALSE, FALSE, FALSE, TRUE, FALSE, TRUE, TRUE),
    stringsAsFactors = FALSE
  )
}
sev_reference <- "LR ohne Unfalltyp"   # fixed in advance, never chosen on test results
sev_extra_reference <- "LR voll"   # second fixed reference: what do the flexible models add to a full LR?
sev_baseline <- "Basislinie"

flag_cols <- c("mit_fussgaenger", "mit_velo", "mit_motorrad")
p_ja <- function(fit, newdata) stats::predict(fit, newdata, type = "prob")$.pred_ja

fit_basis <- function(train, ...) {
  p0 <- mean(train$personenschaden == "ja")
  list(predict = function(newdata) rep(p0, nrow(newdata)), uses = character(), engine = NULL)
}

# Rule: observed training rate by number of vulnerable groups involved (0 / 1 / >= 2).
fit_regel <- function(train, ...) {
  grp <- function(d) pmin(rowSums(d[, flag_cols]), 2L)
  rate <- tapply(train$personenschaden == "ja", factor(grp(train), levels = 0:2), mean)
  rate[is.na(rate)] <- mean(train$personenschaden == "ja")
  list(predict = function(newdata) unname(rate[as.character(grp(newdata))]), uses = flag_cols, engine = NULL)
}

sev_formula <- function(with_typ = TRUE) {
  stats::reformulate(sev_predictors(with_typ), response = "personenschaden")
}

dummy_recipe <- function(train, with_typ = TRUE, one_hot = FALSE) {
  recipes::recipe(sev_formula(with_typ), data = train) |>
    recipes::step_dummy(recipes::all_nominal_predictors(), one_hot = one_hot) |>
    recipes::step_zv(recipes::all_predictors())
}

wrap_workflow <- function(wf_fit, with_typ = TRUE) {
  list(predict = function(newdata) p_ja(wf_fit, newdata), uses = sev_predictors(with_typ), engine = wf_fit)
}

fit_lr <- function(train, with_typ = TRUE, ...) {
  wf <- workflows::workflow(dummy_recipe(train, with_typ), parsnip::logistic_reg() |> parsnip::set_engine("glm"))
  wrap_workflow(suppressWarnings(parsnip::fit(wf, train)), with_typ)
}

spec_glmnet <- function() {
  parsnip::logistic_reg(penalty = hardhat::tune(), mixture = hardhat::tune()) |> parsnip::set_engine("glmnet")
}

spec_rf <- function(s) {
  parsnip::rand_forest(mtry = hardhat::tune(), min_n = hardhat::tune(), trees = s$rf_trees) |>
    parsnip::set_engine("ranger", seed = s$seed, num.threads = s$threads, respect.unordered.factors = "order") |>
    parsnip::set_mode("classification")
}

# Early stopping: up to xgb_trees boosting rounds, stop after xgb_stop rounds without gain on a 15 % holdout.
spec_xgb <- function(s) {
  parsnip::boost_tree(
    trees = s$xgb_trees, tree_depth = hardhat::tune(), learn_rate = hardhat::tune(), min_n = hardhat::tune(),
    loss_reduction = hardhat::tune(), sample_size = hardhat::tune(), mtry = hardhat::tune(), stop_iter = s$xgb_stop
  ) |>
    parsnip::set_engine("xgboost", nthread = s$threads, validation = 0.15, counts = FALSE) |>
    parsnip::set_mode("classification")
}

tuning_workflow <- function(id, train, s) {
  switch(id,
    glmnet = workflows::workflow(dummy_recipe(train), spec_glmnet()),
    rf = workflows::workflow(sev_formula(), spec_rf(s)),
    xgb = workflows::workflow(dummy_recipe(train, one_hot = TRUE), spec_xgb(s))
  )
}

# GAM: smooth effects only for the two cyclic time-of-day / season terms; no year term.
gam_formula <- function() {
  lin <- setdiff(sev_predictors(), c("stunde", "monat"))
  stats::reformulate(c("s(stunde, bs = 'cc', k = 10)", "s(monat, bs = 'cc', k = 8)", lin), response = "y")
}

fit_gam <- function(train, s, ...) {
  train$y <- as.integer(train$personenschaden == "ja")
  m <- mgcv::bam(gam_formula(), data = train, family = stats::binomial(), method = "fREML", discrete = TRUE,
                 nthreads = s$threads, knots = list(stunde = c(-0.5, 23.5), monat = c(0.5, 12.5)))
  list(predict = function(newdata) as.numeric(stats::predict(m, newdata, type = "response")),
       uses = sev_predictors(), engine = m)
}

fit_tuned <- function(id, train, params, s) {
  wf <- tuning_workflow(id, train, s) |> tune::finalize_workflow(params)
  set.seed(s$seed)
  wrap_workflow(parsnip::fit(wf, train))
}

# Effective number of boosting rounds of a fitted xgboost workflow (after early stopping).
xgb_rounds <- function(fit) {
  e <- workflows::extract_fit_engine(fit$engine)
  as.integer(if (!is.null(e$best_iteration)) e$best_iteration else e$niter)
}

# One dispatcher, so the ladder loop is generic. `params` = chosen hyperparameters (tuned models only).
fit_model <- function(id, train, params, s) {
  switch(id,
    basis = fit_basis(train),
    regel = fit_regel(train),
    lr_ohne_typ = fit_lr(train, with_typ = FALSE),
    lr_voll = fit_lr(train, with_typ = TRUE),
    gam = fit_gam(train, s),
    fit_tuned(id, train, params, s)
  )
}
