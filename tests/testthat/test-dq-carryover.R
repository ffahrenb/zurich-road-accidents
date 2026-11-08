# Public-only runs keep the private-track rows of the last private run (marked in `lauf`).
source(file.path(repo_root, "R", "export.R"))

mk <- function(ids, quelle) {
  data.frame(check_id = ids, quelle = quelle, status = "PASS", n_tested = 1L, n_failed = 0L,
             run_utc = "2026-01-01T00:00:00Z", snapshot = "2026-01-01", stringsAsFactors = FALSE)
}

fresh <- mk(c("DQ-U01", "DQ-S01", "DQ-F-UNF"), "unfaelle")
old <- mk(c("DQ-U01", "DQ-X01", "DQ-X02", "DQ-S01"), c("unfaelle", "privat", "privat", "unfaelle"))

test_that("public run carries private rows over in place, marked", {
  out <- carry_over_private(fresh, old)
  expect_equal(out$check_id, c("DQ-U01", "DQ-X01", "DQ-X02", "DQ-S01", "DQ-F-UNF"))
  expect_equal(out$lauf, c("aktuell", rep("letzter privater Lauf", 2), "aktuell", "aktuell"))
  # idempotent: feeding the result back in yields the same table
  expect_equal(carry_over_private(fresh, out), out)
})

test_that("private run is unchanged apart from the lauf column", {
  priv <- rbind(fresh, mk("DQ-X01", "privat"))
  out <- carry_over_private(priv, old)
  expect_equal(out$check_id, priv$check_id)
  expect_true(all(out$lauf == "aktuell"))
})

test_that("export_dq keeps private rows and history across a public run", {
  d <- withr::local_tempdir()
  man <- data.frame(source = "s", file = "f", bytes = 1, sha256 = "x", source_modified = "a",
                    retrieved_utc = "b", licence = "l")
  export_dq(rbind(fresh, mk("DQ-X01", "privat")), man, d)
  export_dq(fresh, man, d)
  res <- utils::read.csv(file.path(d, "dq_ergebnisse.csv"))
  hist <- utils::read.csv(file.path(d, "dq_verlauf.csv"))
  expect_equal(res$lauf[res$check_id == "DQ-X01"], "letzter privater Lauf")
  expect_true("DQ-X01" %in% hist$check_id)
})
