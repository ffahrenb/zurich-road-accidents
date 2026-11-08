# The history files accumulate across runs: this is what the persist job relies on, because every CI run
# starts from the committed export/ and must append to it, not recreate it.
source(file.path(repo_root, "R", "export.R"))

test_that("export_dq appends one block per snapshot to dq_verlauf.csv and keeps older snapshots", {
  d <- withr::local_tempdir()
  man <- data.frame(source = "s", file = "f", bytes = 1, sha256 = "x", source_modified = "a",
                    retrieved_utc = "b", licence = "l", year_from = 2011L, year_to = 2024L)
  mk <- function(snapshot) {
    data.frame(check_id = c("DQ-U01", "DQ-S04"), quelle = "unfaelle", status = "PASS", n_tested = 1L,
               n_failed = 0L, run_utc = paste0(snapshot, "T00:00:00Z"), snapshot = snapshot,
               stringsAsFactors = FALSE)
  }
  export_dq(mk("2026-11-01"), man, d)
  export_dq(mk("2026-12-01"), man, d)
  export_dq(mk("2026-12-01"), man, d)                                   # same date again: replaced, not doubled
  hist <- utils::read.csv(file.path(d, "dq_verlauf.csv"))
  expect_equal(nrow(hist), 4)
  expect_equal(sort(unique(hist$snapshot)), c("2026-11-01", "2026-12-01"))
  expect_true(all(c("year_from", "year_to") %in% names(utils::read.csv(file.path(d, "manifest.csv")))))
})

test_that("snapshot_history.csv keeps earlier snapshots and compares with the latest earlier one", {
  con <- fixture_con()
  load_clean_fixtures(con)
  h <- withr::local_tempfile(fileext = ".csv")
  check_snapshot_delta(con, h, "2026-11-01")
  check_snapshot_delta(con, h, "2026-12-01")
  res <- check_snapshot_delta(con, h, "2027-01-01")
  hist <- utils::read.csv(h)
  expect_equal(sort(unique(hist$snapshot)), c("2026-11-01", "2026-12-01", "2027-01-01"))
  expect_false(grepl("erster Snapshot", res$detail[res$check_id == "DQ-S01"]))   # compared, not re-seeded
})
