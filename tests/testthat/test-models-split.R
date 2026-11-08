test_that("year rule follows the end year E of the automatic range", {
  p <- model_year_plan(2024, 2011)
  expect_equal(p$test, 2022:2024)
  expect_equal(p$validation, 2018:2021)
  expect_equal(p$train_final, 2011:2021)
  expect_length(intersect(p$train_final, p$test), 0)
})

test_that("a partial newest year is excluded before the rule is applied (synthetic range 2011-2025)", {
  acc <- data.frame(jahr = 2011:2025, n = c(rep(5000, 14), 900))   # 2025 incomplete
  res <- resolve_year_range(2011, "auto", acc, avail = list(meteo = 2011:2025))
  expect_equal(res$year_to, 2024)
  p <- model_year_plan(res$year_to, res$year_from)
  expect_equal(range(p$test), c(2022, 2024))
  expect_equal(p$validation, 2018:2021)
  expect_equal(max(p$train_final), 2021)
  # a complete 2025 moves everything by one year
  p25 <- model_year_plan(2025, 2011)
  expect_equal(p25$test, 2023:2025)
  expect_equal(p25$validation, 2019:2022)
})

test_that("a too short range is refused", {
  expect_error(model_year_plan(2016, 2011), "too short")
})

test_that("temporal split: no overlap, rolling origins expand and stay inside training", {
  d <- synthetic_accidents(per_year = 80, last_year = 2020)
  plan <- model_year_plan(2020, 2011)
  sp <- make_split(d, "zeitlich", plan)
  expect_equal(sort(unique(sp$test$jahr)), 2018:2020)
  expect_equal(range(sp$train$jahr), c(2011, 2017))
  expect_length(intersect(sp$train$.row, sp$test$.row), 0)
  expect_equal(nrow(sp$train) + nrow(sp$test), nrow(d))
  expect_equal(nrow(sp$resamples), 4)
  for (i in seq_along(sp$resamples$splits)) {
    s <- sp$resamples$splits[[i]]
    expect_true(max(rsample::analysis(s)$jahr) < min(rsample::assessment(s)$jahr))
    expect_equal(unique(rsample::assessment(s)$jahr), plan$validation[i])
    expect_equal(min(rsample::analysis(s)$jahr), 2011)
  }
})

test_that("no test row id reaches tuning, and the audit catches one that does", {
  d <- synthetic_accidents(per_year = 80, last_year = 2020)
  plan <- model_year_plan(2020, 2011)
  for (kind in c("zeitlich", "zufaellig")) {
    sp <- make_split(d, kind, plan)
    expect_length(intersect(resample_row_ids(sp$resamples), sp$test$.row), 0)
    expect_true(assert_resamples_in_train(sp$train, sp$resamples))
    # tuning functions get the training data and its resamples only: shrinking train must be refused
    expect_error(assert_resamples_in_train(sp$train[-1, ], sp$resamples), "outside the training set")
    expect_error(tune_model("glmnet", sp$train[-seq_len(100), ], sp$resamples, tiny_settings()), "outside")
  }
  # a leaking resample set (built from the full data) is refused
  leak <- rolling_origin_sets(d, plan$test)   # validation years inside the test years
  sp <- make_split(d, "zeitlich", plan)
  expect_error(assert_resamples_in_train(sp$train, leak), "outside the training set")
})

test_that("random split: same seed same rows; folds are stratified 5-fold inside the training part", {
  d <- synthetic_accidents(per_year = 80, last_year = 2020)
  plan <- model_year_plan(2020, 2011)
  a <- make_split(d, "zufaellig", plan, seed = 9L)
  b <- make_split(d, "zufaellig", plan, seed = 9L)
  expect_identical(a$test$.row, b$test$.row)
  expect_identical(a$resamples$splits[[3]]$in_id, b$resamples$splits[[3]]$in_id)
  expect_equal(nrow(a$resamples), 5)
  expect_equal(nrow(a$train), round(0.8 * nrow(d)), tolerance = 0.01)
  expect_length(intersect(resample_row_ids(a$resamples), a$test$.row), 0)
  # regime subsets exist for the random split only
  expect_setequal(names(eval_subsets(a$test, "zufaellig")), c("alle", "ohne_parkier_tier", "vor_2015", "ab_2015"))
  expect_setequal(names(eval_subsets(a$test, "zeitlich")), c("alle", "ohne_parkier_tier"))
})

test_that("jahr is never a predictor; the regime indicator ab_2015 is", {
  for (with_typ in c(TRUE, FALSE)) {
    pr <- sev_predictors(with_typ)
    expect_false("jahr" %in% pr)
    expect_true("ab_2015" %in% pr)
    expect_false(any(grepl("jahr", all.vars(sev_formula(with_typ)[[3]]))))
  }
  expect_false("typ" %in% sev_predictors(FALSE))
  expect_false(any(grepl("jahr", deparse(gam_formula()))))
  baked <- recipes::bake(recipes::prep(dummy_recipe(synthetic_accidents(40, 2016))), new_data = NULL)
  expect_false(any(grepl("jahr", names(baked))))
  expect_equal(sev_reference, "LR ohne Unfalltyp")
})
