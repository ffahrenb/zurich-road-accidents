# Automatic year range (config: years.to = auto).
# The published range ends at the latest year for which ALL required inputs exist. Pure functions
# on plain inputs, so the logic is unit-tested without network (tests/testthat/test-years.R).

min_year_ratio <- 0.8   # newest accident year below 80 % of the year before = partial, excluded

# Years found in resource names such as "ugz_ogd_meteo_h1_2024.csv" for a "..._{year}.csv" pattern.
years_from_names <- function(names, pattern) {
  rx <- paste0("^", gsub("\\{year\\}", "([0-9]{4})", gsub("([.])", "\\\\\\1", pattern)), "$")
  hit <- regmatches(names, regexec(rx, names))
  sort(as.integer(vapply(Filter(length, hit), `[`, "", 2)))
}

# Last year y such that every year from..y is present (a gap ends the range).
contiguous_to <- function(years, from) {
  if (!from %in% years) return(NA_integer_)
  y <- from
  while ((y + 1L) %in% years) y <- y + 1L
  as.integer(y)
}

# acc:   data.frame(jahr, n), accident rows per year in the downloaded file
# avail: named list, source key -> integer years that exist as per-year resource
# pop_max: newest year in the population file (NA if unknown). Does NOT limit the range.
resolve_year_range <- function(from, to, acc, avail, pop_max = NA_integer_) {
  acc <- acc[acc$jahr >= from, , drop = FALSE]
  acc <- acc[order(acc$jahr), , drop = FALSE]
  if (nrow(acc) == 0) stop("no accident rows from ", from, " onwards", call. = FALSE)
  newest <- max(acc$jahr)
  n_of <- function(y) if (y %in% acc$jahr) acc$n[acc$jahr == y] else NA_real_
  n_newest <- n_of(newest)
  n_prev <- n_of(newest - 1L)
  ratio <- n_newest / n_prev
  mode <- if (identical(to, "auto")) "auto" else "fest"
  partial <- mode == "auto" && !is.na(ratio) && ratio < min_year_ratio
  acc_to <- if (mode == "fest") as.integer(to) else if (partial) newest - 1L else newest
  src_to <- vapply(avail, contiguous_to, integer(1), from = from)
  if (mode == "auto") {
    if (anyNA(src_to)) {
      stop("no per-year resource for ", from, " in: ", paste(names(src_to)[is.na(src_to)], collapse = ", "),
           call. = FALSE)
    }
    year_to <- min(c(acc_to, src_to))
    limited_by <- names(src_to)[src_to < acc_to]
  } else {
    year_to <- acc_to
    limited_by <- character()
  }
  if (year_to < from) stop("resolved range is empty: ", from, "-", year_to, call. = FALSE)
  list(
    year_from = as.integer(from), year_to = as.integer(year_to), mode = mode,
    accident_max = as.integer(newest), accident_to = as.integer(acc_to),
    partial_excluded = partial, n_newest = n_newest, n_prev = n_prev, ratio = ratio,
    limited_by = limited_by, source_max = src_to, pop_max = as.integer(pop_max)
  )
}

# One row per run for the snapshot dir (years.csv) and the committed history (jahresbereich.csv).
years_row <- function(res, snapshot) {
  data.frame(
    snapshot = as.character(snapshot), jahr_von = res$year_from, jahr_bis = res$year_to, modus = res$mode,
    unfaelle_jahr_max = res$accident_max, unfaelle_n_neuestes = res$n_newest, unfaelle_n_vorjahr = res$n_prev,
    teiljahr_ausgeschlossen = res$partial_excluded,
    begrenzt_durch = paste(res$limited_by, collapse = ","),
    bev_jahr_max = res$pop_max,
    stringsAsFactors = FALSE
  )
}

# --- network / file side: collects the inputs for resolve_year_range ---------------------------

accident_year_counts <- function(parquet_path) {
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbGetQuery(con, sprintf(
    "SELECT AccidentYear::INTEGER AS jahr, count(*)::INTEGER AS n FROM read_parquet('%s') GROUP BY 1 ORDER BY 1",
    parquet_path))
}

population_max_year <- function(csv_path) {
  x <- utils::read.csv(csv_path, fileEncoding = "UTF-8-BOM")
  max(as.integer(x$StichtagDatJahr))
}

# fixed: manifest rows of the single-file sources already downloaded (unfaelle, bevoelkerung).
resolve_snapshot_years <- function(cfg, fixed) {
  acc_path <- fixed$path[fixed$source == "unfaelle"][1]
  pop_path <- fixed$path[fixed$source == "bevoelkerung"]
  keys <- names(Filter(function(s) !is.null(s[["resource_pattern"]]), cfg$sources))
  avail <- stats::setNames(lapply(keys, function(k) {
    src <- cfg$sources[[k]]
    years_from_names(vapply(ckan_package(cfg, src$ckan_id)$resources, function(r) r$name, ""),
                     src$resource_pattern)
  }), keys)
  resolve_year_range(cfg$years$from, cfg$years$to, accident_year_counts(acc_path), avail,
                     if (length(pop_path)) population_max_year(pop_path) else NA_integer_)
}

# --- downstream: resolved range from the snapshot ----------------------------------------------

years_file <- function(manifest) {
  file.path(dirname(dirname(manifest$path[1])), "years.csv")
}

read_years <- function(manifest) utils::read.csv(years_file(manifest), stringsAsFactors = FALSE)

# cfg with years$from / years$to replaced by the resolved numbers (what SQL, DQ and DCAT use).
apply_years <- function(cfg, years_info) {
  cfg$years$from <- as.integer(years_info$jahr_von)
  cfg$years$to <- as.integer(years_info$jahr_bis)
  cfg
}
