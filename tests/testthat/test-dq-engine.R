# DQ engine tests with DELIBERATELY BROKEN FIXTURES.
# Principle: a check that has never been seen to fail proves nothing. Each test
# corrupts one clean fixture in exactly one way and asserts the matching check fires.

ids <- c("U01", "U02", "U04", "M05")

test_that("clean fixtures: all representative checks PASS", {
  con <- fixture_con()
  load_clean_fixtures(con)
  res <- run_real_checks(con, ids)
  expect_equal(sort(res$check_id), sort(paste0("DQ-", ids)))
  expect_true(all(res$status == "PASS"), info = paste(res$check_id, res$status, collapse = ", "))
  expect_true(dq_gate(res))
})

test_that("duplicate accident ID fires DQ-U01 (STOP)", {
  con <- fixture_con()
  load_clean_fixtures(con)
  DBI::dbExecute(con, "INSERT INTO raw_unfaelle VALUES ('A001', 2020)")
  res <- run_real_checks(con, ids)
  expect_equal(status_of(res, "DQ-U01"), "STOP")
  expect_equal(res$n_failed[res$check_id == "DQ-U01"], 1)
  expect_error(dq_gate(res), "DQ-U01")
})

test_that("missing mandatory field fires DQ-U02 (STOP)", {
  con <- fixture_con()
  load_clean_fixtures(con)
  DBI::dbExecute(con, "UPDATE stg_unfaelle SET stunde = NULL WHERE unfall_id = 'A005'")
  res <- run_real_checks(con, ids)
  expect_equal(status_of(res, "DQ-U02"), "STOP")
  expect_equal(res$n_failed[res$check_id == "DQ-U02"], 1)
})

test_that("coordinate outside Zuerich fires DQ-U04 (STOP)", {
  con <- fixture_con()
  load_clean_fixtures(con)
  DBI::dbExecute(con, "UPDATE stg_unfaelle SET e_lv95 = 2600000 WHERE unfall_id = 'A007'")  # Basel-ish
  res <- run_real_checks(con, ids)
  expect_equal(status_of(res, "DQ-U04"), "STOP")
  expect_error(dq_gate(res), "DQ-U04")
})

test_that("out-of-range cleaned meteo value fires DQ-M05 (STOP)", {
  con <- fixture_con()
  load_clean_fixtures(con)
  DBI::dbExecute(con, "INSERT INTO stg_meteo VALUES (99.9, 1, 50, 2)")   # 99.9 degC
  res <- run_real_checks(con, ids)
  expect_equal(status_of(res, "DQ-M05"), "STOP")
})

test_that("a breakage only trips its own check", {
  con <- fixture_con()
  load_clean_fixtures(con)
  DBI::dbExecute(con, "UPDATE stg_unfaelle SET n_lv95 = 0 WHERE unfall_id = 'A002'")
  res <- run_real_checks(con, ids)
  expect_equal(res$check_id[res$status != "PASS"], "DQ-U04")
})

test_that("checks needing absent tables are skipped, not failed", {
  con <- fixture_con()
  load_clean_fixtures(con)
  f <- Sys.glob(file.path(repo_root, "sql", "dq", "X01_*.sql"))
  expect_null(run_sql_checks(con, f, params = list()))   # stg_x_zeit absent (public track only)
})

# --- snapshot history ---------------------------------------------------------

write_history <- function(path, n2020, n2021, snapshot = "2026-01-01") {
  utils::write.csv(data.frame(jahr = c(2020L, 2021L), n = c(n2020, n2021), snapshot = snapshot),
                   path, row.names = FALSE)
}

test_that("snapshot shrink > 10 % fires DQ-S02 (STOP) and DQ-S01 (WARN)", {
  con <- fixture_con()
  load_clean_fixtures(con)             # 10 + 10 rows
  h <- withr::local_tempfile(fileext = ".csv")
  write_history(h, 100, 100)                                 # previous: 200 rows -> now 20
  res <- check_snapshot_delta(con, h, "2026-02-01")
  expect_equal(status_of(res, "DQ-S02"), "STOP")
  expect_equal(status_of(res, "DQ-S01"), "WARN")
  expect_error(dq_gate(res), "DQ-S02")
})

test_that("unchanged snapshot passes; first snapshot creates the reference", {
  con <- fixture_con()
  load_clean_fixtures(con)
  h <- withr::local_tempfile(fileext = ".csv")
  res1 <- check_snapshot_delta(con, h, "2026-01-01")         # no history yet
  expect_true(all(res1$status == "PASS"))
  expect_true(file.exists(h))
  res2 <- check_snapshot_delta(con, h, "2026-02-01")         # identical counts
  expect_true(all(res2$status == "PASS"))
})

test_that("small drift (5 %) warns (S01) but does not stop (S02)", {
  con <- fixture_con()
  load_clean_fixtures(con)
  h <- withr::local_tempfile(fileext = ".csv")
  write_history(h, 10.5, 10.5)
  res <- check_snapshot_delta(con, h, "2026-02-01")
  expect_equal(status_of(res, "DQ-S01"), "WARN")
  expect_equal(status_of(res, "DQ-S02"), "PASS")
})

# --- gate and status logic ----------------------------------------------------

gate_row <- function(status) {
  data.frame(check_id = "DQ-T", titel_de = "Test", detail = "d", status = status,
             stringsAsFactors = FALSE)
}

test_that("dq_gate errors on STOP and passes on WARN/PASS", {
  expect_error(dq_gate(gate_row("STOP")), "STOP")
  expect_error(dq_gate(rbind(gate_row("PASS"), gate_row("STOP"))), "1 STOP")
  expect_true(dq_gate(gate_row("WARN")))
  expect_true(dq_gate(gate_row("PASS")))
})

test_that("check_status honours tolerance and treats an unrunnable check as failed", {
  expect_equal(check_status(100, 0, "STOP", 0), "PASS")
  expect_equal(check_status(100, 1, "STOP", 0), "STOP")
  expect_equal(check_status(100, 1, "WARN", 2), "PASS")
  expect_equal(check_status(100, 5, "WARN", 2), "WARN")
  expect_equal(check_status(0, 3, "STOP", 0), "STOP")
  expect_equal(check_status(100, NA, "STOP", 0), "STOP")
})

# --- catalogue hygiene ----------------------------------------------------------

test_that("every sql/dq file carries the full header metadata", {
  files <- Sys.glob(file.path(repo_root, "sql", "dq", "*.sql"))
  expect_gt(length(files), 0)
  need <- c("id", "quelle", "dimension", "schwere", "titel_de", "titel_en")
  m <- lapply(files, parse_check_header)
  for (i in seq_along(files)) {
    expect_true(all(need %in% names(m[[i]])), info = basename(files[i]))
    expect_true(m[[i]]$schwere %in% c("STOP", "WARN"), info = basename(files[i]))
  }
  expect_false(anyDuplicated(vapply(m, `[[`, "", "id")) > 0)
})

test_that("parse_check_header reads metadata lines", {
  f <- withr::local_tempfile(fileext = ".sql")
  writeLines(c("-- id: DQ-Z01", "-- schwere: WARN", "-- toleranz_pct: 2", "SELECT 1"), f)
  m <- parse_check_header(f)
  expect_equal(m$id, "DQ-Z01")
  expect_equal(m$toleranz_pct, "2")
})
