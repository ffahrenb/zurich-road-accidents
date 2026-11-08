# Automatic year range: resolver (pure functions, mock inputs, no network), range history checks,
# and the population carry-forward in the mart.
source(file.path(repo_root, "R", "years.R"))

acc_counts <- function(last, n_last = 5400, from = 2011) {
  years <- from:last
  data.frame(jahr = years, n = c(rep(5200, length(years) - 1), n_last))
}
avail_to <- function(meteo, luft = meteo, from = 2011) list(meteo = from:meteo, luft = from:luft)

test_that("years_from_names parses per-year resource names and ignores the rest", {
  nm <- c("ugz_ogd_meteo_h1_2023.csv", "ugz_ogd_meteo_h1_2024.csv", "ugz_ogd_meteo_h1.parquet",
          "ugz_ogd_meteo_h1_2024.csv.bak", "uzg_ogd_metadaten.json", "ugz_ogd_meteo_h1_1992.csv")
  expect_equal(years_from_names(nm, "ugz_ogd_meteo_h1_{year}.csv"), c(1992L, 2023L, 2024L))
  expect_equal(years_from_names(character(), "x_{year}.csv"), integer())
})

test_that("normal case: all sources reach the newest accident year", {
  r <- resolve_year_range(2011, "auto", acc_counts(2025), avail_to(2026), pop_max = 2025)
  expect_equal(c(r$year_from, r$year_to), c(2011L, 2025L))
  expect_false(r$partial_excluded)
  expect_equal(r$limited_by, character())
  expect_equal(r$accident_max, 2025L)
})

test_that("current published state resolves to 2011-2024", {
  r <- resolve_year_range(2011, "auto", acc_counts(2024), avail_to(2026), pop_max = 2025)
  expect_equal(r$year_to, 2024L)
})

test_that("partial newest accident year (< 80 % of the year before) is excluded", {
  r <- resolve_year_range(2011, "auto", acc_counts(2025, n_last = 2000), avail_to(2026))
  expect_equal(r$year_to, 2024L)
  expect_true(r$partial_excluded)
  expect_equal(r$accident_max, 2025L)
  expect_equal(r$accident_to, 2024L)
  expect_equal(r$ratio, 2000 / 5200)
})

test_that("a sparse future year without its predecessor is not published (fail closed)", {
  acc <- rbind(acc_counts(2024), data.frame(jahr = 2026, n = 3))
  r <- resolve_year_range(2011, "auto", acc, avail_to(2026))
  expect_equal(r$year_to, 2024L)
  expect_true(r$partial_excluded)
  expect_equal(r$excluded_years, 2026L)
})

test_that("several trailing partial years are dropped iteratively", {
  acc <- data.frame(jahr = 2011:2026, n = c(rep(5200, 14), 2000, 30))
  r <- resolve_year_range(2011, "auto", acc, avail_to(2026))
  expect_equal(r$year_to, 2024L)
  expect_equal(r$excluded_years, c(2025L, 2026L))
  expect_equal(r$accident_max, 2026L)
  # a partial year followed by a complete-looking one is still dropped only from the end
  acc2 <- data.frame(jahr = 2011:2026, n = c(rep(5200, 14), 2000, 5000))
  expect_equal(resolve_year_range(2011, "auto", acc2, avail_to(2026))$year_to, 2026L)
})

test_that("a gap in the accident years ends the range before the gap and is reported", {
  acc <- data.frame(jahr = c(2011:2017, 2019:2024), n = 5200)
  r <- resolve_year_range(2011, "auto", acc, avail_to(2026))
  expect_equal(r$year_to, 2017L)
  expect_equal(r$excluded_years, 2019:2024)
  expect_true(r$partial_excluded)
  res <- check_year_range(years_row(r, "2026-01-01"), withr::local_tempfile(fileext = ".csv"), "2026-01-01")
  expect_equal(status_of(res, "DQ-S03"), "WARN")
  expect_match(res$detail[res$check_id == "DQ-S03"], "2019, 2020")
})

test_that("DQ-S03 detail names every excluded year", {
  acc <- data.frame(jahr = 2011:2026, n = c(rep(5200, 14), 2000, 30))
  r <- resolve_year_range(2011, "auto", acc, avail_to(2026))
  res <- check_year_range(years_row(r, "2026-01-01"), withr::local_tempfile(fileext = ".csv"), "2026-01-01")
  expect_match(res$detail[res$check_id == "DQ-S03"], "ausgelassen: 2025, 2026")
})

test_that("the 80 % limit is inclusive: exactly 80 % is published", {
  r <- resolve_year_range(2011, "auto", acc_counts(2025, n_last = 4160), avail_to(2026))
  expect_false(r$partial_excluded)
  expect_equal(r$year_to, 2025L)
})

test_that("a per-year source without the newest year limits the range and is named", {
  r <- resolve_year_range(2011, "auto", acc_counts(2025), list(meteo = 2011:2024, luft = 2011:2026))
  expect_equal(r$year_to, 2024L)
  expect_equal(r$limited_by, "meteo")
  expect_false(r$partial_excluded)
  r2 <- resolve_year_range(2011, "auto", acc_counts(2025), list(meteo = 2011:2024, luft = 2011:2023))
  expect_equal(r2$year_to, 2023L)
  expect_equal(r2$limited_by, c("meteo", "luft"))
})

test_that("a gap in the per-year resources ends the range before the gap", {
  r <- resolve_year_range(2011, "auto", acc_counts(2025),
                          list(meteo = c(2011:2019, 2021:2026), luft = 2011:2026))
  expect_equal(r$year_to, 2019L)
  expect_equal(r$limited_by, "meteo")
})

test_that("a lagging population file does not limit the range, but is reported", {
  r <- resolve_year_range(2011, "auto", acc_counts(2025), avail_to(2026), pop_max = 2023)
  expect_equal(r$year_to, 2025L)
  expect_equal(r$pop_max, 2023L)
})

test_that("a missing start year or an empty range is an error, not a silent shrink", {
  expect_error(resolve_year_range(2011, "auto", acc_counts(2025), list(meteo = 2012:2026)), "no per-year resource")
  expect_error(resolve_year_range(2030, "auto", acc_counts(2025), avail_to(2026, from = 2030)), "no accident rows")
})

test_that("a numeric years.to pins the range and skips the automatic guards", {
  r <- resolve_year_range(2011, 2023, acc_counts(2025, n_last = 100), avail_to(2020))
  expect_equal(r$year_to, 2023L)
  expect_equal(r$mode, "fest")
  expect_false(r$partial_excluded)
})

test_that("years_row / apply_years round-trip through the snapshot CSV", {
  r <- resolve_year_range(2011, "auto", acc_counts(2025, n_last = 2000), avail_to(2026), pop_max = 2025)
  f <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(years_row(r, "2026-12-01"), f, row.names = FALSE)
  info <- utils::read.csv(f, stringsAsFactors = FALSE)
  expect_equal(c(info$jahr_von, info$jahr_bis), c(2011, 2024))
  expect_true(info$teiljahr_ausgeschlossen)
  cfg <- apply_years(list(years = list(from = 2011, to = "auto")), info)
  expect_equal(c(cfg$years$from, cfg$years$to), c(2011L, 2024L))
})

# --- range history checks --------------------------------------------------------------------

info_for <- function(to, partial = FALSE, limited = "") {
  r <- resolve_year_range(2011, "auto", acc_counts(to + partial, n_last = if (partial) 2000 else 5400),
                          avail_to(to + 2))
  row <- years_row(r, "x")
  row$begrenzt_durch <- limited
  row
}

test_that("range shrink against the previous snapshot fires DQ-S04 (STOP) and is not recorded", {
  h <- withr::local_tempfile(fileext = ".csv")
  res0 <- check_year_range(info_for(2025), h, "2026-01-01")
  expect_equal(status_of(res0, "DQ-S04"), "PASS")                      # first snapshot: reference
  res <- check_year_range(info_for(2024), h, "2026-02-01")
  expect_equal(status_of(res, "DQ-S04"), "STOP")
  expect_error(dq_gate(res), "DQ-S04")
  expect_match(res$detail[res$check_id == "DQ-S04"], "2011–2024, vorher 2011–2025")
  hist <- utils::read.csv(h)
  expect_equal(hist$snapshot, "2026-01-01")                            # shrunk row NOT written
  res2 <- check_year_range(info_for(2024), h, "2026-02-02")            # rerun cannot heal it
  expect_equal(status_of(res2, "DQ-S04"), "STOP")
})

test_that("a higher start year is a shrink too", {
  h <- withr::local_tempfile(fileext = ".csv")
  check_year_range(info_for(2024), h, "2026-01-01")
  later <- info_for(2024)
  later$jahr_von <- 2012L
  expect_equal(status_of(check_year_range(later, h, "2026-02-01"), "DQ-S04"), "STOP")
})

test_that("unchanged or growing range passes and history appends one row per snapshot date", {
  h <- withr::local_tempfile(fileext = ".csv")
  check_year_range(info_for(2024), h, "2026-01-01")
  expect_equal(status_of(check_year_range(info_for(2024), h, "2026-02-01"), "DQ-S04"), "PASS")
  expect_equal(status_of(check_year_range(info_for(2025), h, "2026-03-01"), "DQ-S04"), "PASS")
  check_year_range(info_for(2025), h, "2026-03-01")                    # same date again: replaced
  hist <- utils::read.csv(h)
  expect_equal(hist$snapshot, c("2026-01-01", "2026-02-01", "2026-03-01"))
  expect_equal(hist$jahr_bis, c(2024, 2024, 2025))
})

test_that("partial year fires DQ-S03 (WARN), a limiting source fires DQ-S05 (WARN), neither stops", {
  h <- withr::local_tempfile(fileext = ".csv")
  res <- check_year_range(info_for(2024, partial = TRUE), h, "2026-01-01")
  expect_equal(status_of(res, "DQ-S03"), "WARN")
  expect_equal(status_of(res, "DQ-S05"), "PASS")
  expect_true(dq_gate(res))
  h2 <- withr::local_tempfile(fileext = ".csv")
  res2 <- check_year_range(info_for(2024, limited = "meteo"), h2, "2026-01-01")
  expect_equal(status_of(res2, "DQ-S05"), "WARN")
  expect_equal(status_of(res2, "DQ-S03"), "PASS")
  expect_match(res2$detail[res2$check_id == "DQ-S05"], "meteo")
})

test_that("an all-empty begrenzt_durch column (read back as NA) counts as not limited", {
  h <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(years_row(resolve_year_range(2011, "auto", acc_counts(2024), avail_to(2026)), "2026-01-01"),
                   h, row.names = FALSE)
  info <- utils::read.csv(h, stringsAsFactors = FALSE)
  expect_true(is.na(info$begrenzt_durch))
  hist <- withr::local_tempfile(fileext = ".csv")
  expect_equal(status_of(check_year_range(info, hist, "2026-02-01"), "DQ-S05"), "PASS")
})

# --- population carry-forward (sql/mart/02_mart_aggregate.sql, DQ-B03) --------------------------

test_that("mart_quartier carries the newest population year forward and DQ-B03 warns", {
  con <- fixture_con()
  DBI::dbWriteTable(con, "mart_unfaelle", data.frame(
    jahr = c(2023L, 2024L, 2025L, 2025L), monat = 1L, wochentag = 1L, stunde = 8L,
    schwere_kurz = "Leichtverletzte", mit_velo = FALSE, mit_fussgaenger = FALSE, mit_motorrad = FALSE,
    personenschaden = TRUE, quartier_nr = 11L, tempo_klasse = "Tempo 50"))
  DBI::dbWriteTable(con, "stg_quartiere", data.frame(quartier_nr = 11L, quartier = "Rathaus", kreis_nr = 1L))
  DBI::dbWriteTable(con, "stg_bevoelkerung", data.frame(
    jahr = c(2023L, 2024L), quartier_nr = 11L, quartier = "Rathaus", einwohner = c(3000L, 4000L)))
  DBI::dbWriteTable(con, "stg_meteo", data.frame(
    ts_utc = as.POSIXct("2024-01-01", tz = "UTC"), station = "S", temperatur_c = 1, regen_min = 0))
  run_sql_file(con, file.path(repo_root, "sql", "mart", "02_mart_aggregate.sql"), list(station = "S"))
  m <- DBI::dbGetQuery(con, "SELECT jahr, einwohner, einwohner_jahr, personenschaden_pro_1000 AS r
                             FROM mart_quartier ORDER BY jahr")
  expect_equal(m$einwohner, c(3000, 4000, 4000))
  expect_equal(m$einwohner_jahr, c(2023, 2024, 2024))
  expect_equal(m$r[3], 0.5)                                            # two cases per 4000 residents
  res <- run_real_checks(con, "B03")
  expect_equal(status_of(res, "DQ-B03"), "WARN")
  expect_match(res$detail, "2025 mit Stand 2024")
  DBI::dbExecute(con, "INSERT INTO stg_bevoelkerung VALUES (2025, 11, 'Rathaus', 4100)")
  run_sql_file(con, file.path(repo_root, "sql", "mart", "02_mart_aggregate.sql"), list(station = "S"))
  expect_equal(status_of(run_real_checks(con, "B03"), "DQ-B03"), "PASS")
})
