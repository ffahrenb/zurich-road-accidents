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
  d$monat <- factor(d$monat)
  d$jahr <- factor(d$jahr)

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
