test_that("render_sql fills every placeholder", {
  expect_equal(render_sql("a {{x}} b {{y}} {{x}}", list(x = 1, y = "z")), "a 1 b z 1")
})

test_that("render_sql errors on an unfilled placeholder", {
  expect_error(render_sql("WHERE jahr >= {{year_from}} AND s = {{station}}", list(year_from = 2011)),
               "unfilled SQL parameter.*station")
  expect_error(render_sql("{{a}} {{b}}", list()), "{{a}}, {{b}}", fixed = TRUE)
})

test_that("every pipeline SQL file renders with the parameters build_warehouse supplies", {
  nms <- c("unfaelle", "meteo", "luft", "bevoelkerung", "quartiere", "schulen", "tempo",
           "year_from", "year_to", "school_radius_m", "tempo_radius_m", "station", "x_from", "x_to")
  params <- stats::setNames(as.list(rep("0", length(nms))), nms)
  for (f in Sys.glob(file.path(repo_root, "sql", "*", "*.sql"))) {
    sql <- paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    expect_no_error(render_sql(sql, params))
  }
})

test_that("run_sql_file executes statements in order against DuckDB", {
  con <- fixture_con()
  f <- withr::local_tempfile(fileext = ".sql")
  writeLines(c("CREATE TABLE t AS SELECT {{n}} AS v;", "INSERT INTO t VALUES (2);"), f)
  run_sql_file(con, f, list(n = 1))
  expect_equal(DBI::dbGetQuery(con, "SELECT sum(v) AS s FROM t")$s, 3)
  writeLines("SELECT {{missing}};", f)
  expect_error(run_sql_file(con, f, list()), "unfilled")
})
