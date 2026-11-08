# Severity ladder: data, year rule, splits.
# Question: does an accident involve personal injury (yes/no)? Association, not a prediction tool.

sev_seed <- 2026L
parkier_tier_typen <- c("Parkierunfall", "Tierunfall")
regime_year <- 2015L   # recording practice for property-damage accidents changed in 2015

# Year rule, derived from E = last year of the automatic range (only complete years):
# test = E-2..E, rolling validation origins = E-6..E-3 (expanding window), final training = from..E-3.
model_year_plan <- function(year_to, year_from = 2011L) {
  e <- as.integer(year_to)
  plan <- list(
    year_from = as.integer(year_from), year_to = e, test = (e - 2L):e, validation = (e - 6L):(e - 3L),
    train_final = as.integer(year_from):(e - 3L)
  )
  if (plan$validation[1] <= plan$year_from) {
    stop("range ", year_from, "-", e, " too short for 4 validation origins + 3 test years", call. = FALSE)
  }
  plan
}

# Predictors of every model. `jahr` is never one of them: the regime indicator ab_2015 replaces it, so no model
# extrapolates a year trend beyond the last training year.
sev_predictors <- function(with_typ = TRUE) {
  c("stunde", "wochentag", "monat", "ab_2015", if (with_typ) "typ",
    "strassenart", "mit_fussgaenger", "mit_velo", "mit_motorrad", "tempo_klasse", "nahe_schule", "kreis_nr", "nacht")
}

# Rows ordered by unfall_id (stable row ids .row across runs). Never exported.
load_severity_data <- function(db_path) {
  con <- db_connect(db_path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  d <- DBI::dbGetQuery(con, "
    SELECT personenschaden, stunde, wochentag, monat, jahr, typ, strassenart,
           mit_fussgaenger, mit_velo, mit_motorrad, tempo_klasse, nahe_schule,
           coalesce(kreis_nr, 0) AS kreis_nr
    FROM mart_unfaelle ORDER BY unfall_id")
  prepare_severity_data(d)
}

prepare_severity_data <- function(d) {
  d$parkier_tier <- d$typ %in% parkier_tier_typen
  d$personenschaden <- factor(ifelse(d$personenschaden, "ja", "nein"), levels = c("ja", "nein"))
  for (v in c("typ", "strassenart", "tempo_klasse", "kreis_nr", "wochentag")) d[[v]] <- factor(d[[v]])
  for (v in c("mit_fussgaenger", "mit_velo", "mit_motorrad", "nahe_schule")) d[[v]] <- as.integer(d[[v]])
  d$nacht <- as.integer(d$stunde < 6 | d$stunde >= 22)
  d$ab_2015 <- as.integer(d$jahr >= regime_year)
  d$.row <- seq_len(nrow(d))
  d
}

# Resamples inside the training part only. Rolling origin, expanding window: analysis = all years before the
# validation year (back to the first year in `train`), assessment = the validation year.
rolling_origin_sets <- function(train, validation_years) {
  splits <- lapply(validation_years, function(v) {
    rsample::make_splits(list(analysis = which(train$jahr < v), assessment = which(train$jahr == v)), data = train)
  })
  rsample::manual_rset(splits, paste("Validierung", validation_years))
}

# A split = train, test and the resamples used for tuning. Tuning only ever sees `train`.
make_split <- function(d, kind, plan, seed = sev_seed) {
  if (kind == "zeitlich") {
    train <- d[d$jahr %in% plan$train_final, ]
    test <- d[d$jahr %in% plan$test, ]
    resamples <- rolling_origin_sets(train, plan$validation)
  } else {
    set.seed(seed)
    s <- rsample::initial_split(d, prop = 0.8, strata = personenschaden)
    train <- rsample::training(s)
    test <- rsample::testing(s)
    resamples <- rsample::vfold_cv(train, v = 5, strata = personenschaden)
  }
  rownames(train) <- rownames(test) <- NULL
  if (length(intersect(train$.row, test$.row))) stop("train and test overlap", call. = FALSE)
  list(kind = kind, train = train, test = test, resamples = resamples)
}

# Row ids a tuning run can see. Used by the audit: must be a subset of the training ids.
resample_row_ids <- function(resamples) {
  sort(unique(unlist(lapply(resamples$splits, function(s) {
    c(rsample::analysis(s)$.row, rsample::assessment(s)$.row)
  }))))
}

assert_resamples_in_train <- function(train, resamples) {
  if (!all(resample_row_ids(resamples) %in% train$.row)) {
    stop("tuning resamples reach rows outside the training set", call. = FALSE)
  }
  invisible(TRUE)
}

# Evaluation subsets on the test rows ("auswertung"). Regime subsets exist for the random split only:
# the temporal test years all lie after the regime change.
eval_subsets <- function(test, kind) {
  s <- list(alle = rep(TRUE, nrow(test)), ohne_parkier_tier = !test$parkier_tier)
  if (kind == "zufaellig") {
    s$vor_2015 <- test$jahr < regime_year
    s$ab_2015 <- test$jahr >= regime_year
  }
  s
}
