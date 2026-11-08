# Shared helpers: load the real pipeline code, build fixture databases.

repo_root <- normalizePath(testthat::test_path("..", ".."), mustWork = TRUE)

for (f in c("db.R", "dq.R")) source(file.path(repo_root, "R", f), local = FALSE)

# Fixture DB: in-memory DuckDB. Uses the production connector when the
# pre-installed extensions exist, else a plain connection (checks need no spatial).
fixture_con <- function(env = parent.frame()) {
  con <- tryCatch(db_connect(":memory:"),
                  error = function(e) DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:"))
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE), envir = env)
  con
}

# Clean baseline fixtures; every table passes every check under test.
load_clean_fixtures <- function(con) {
  DBI::dbWriteTable(con, "raw_unfaelle", data.frame(
    accidentuid = sprintf("A%03d", 1:20), AccidentYear = rep(c(2020L, 2021L), each = 10),
    stringsAsFactors = FALSE))
  DBI::dbWriteTable(con, "stg_unfaelle", data.frame(
    unfall_id = sprintf("A%03d", 1:20), schwere_code = 3L, jahr = 2020L, monat = 6L,
    wochentag = 3L, stunde = 12L, e_lv95 = 2683000, n_lv95 = 1248000,
    stringsAsFactors = FALSE))
  DBI::dbWriteTable(con, "stg_meteo", data.frame(
    temperatur_c = c(5, 12.5, 25), regen_min = c(0, 3, 10),
    feuchte_pct = c(40, 70, 100), wind_ms = c(0, 2, 8)))
  invisible(con)
}

# Run the REAL check files (sql/dq/<id>_*.sql) for the given ids.
run_real_checks <- function(con, ids) {
  files <- unlist(lapply(ids, function(i) {
    Sys.glob(file.path(repo_root, "sql", "dq", paste0(i, "_*.sql"))) }))
  stopifnot(length(files) == length(ids))
  run_sql_checks(con, files,
                 params = list(year_from = 2011, year_to = 2025, station = "Zch_Stampfenbachstrasse"))
}

status_of <- function(res, id) res$status[res$check_id == id]
