# PRIVACY GATE. Fails closed: anything not explicitly allowed is a failure.
#
# Threat model: a private CSV with exact accident timestamps feeds "Track X".
# The public data only has year/month/weekday/hour. Whoever can publish a Track X
# output keyed by date/day/week/date-hour (or raw hourly weather values, which
# identify a date) can re-identify the exact date of public accident rows.
# Allowed: model coefficients and coarse aggregates (rain x temperature bin), n >= 10.
#
# Runs in CI without private data. The repo root is taken from ZH_PRIVACY_ROOT
# (used by test-privacy-selftest.R to feed deliberately bad trees), else the real repo.
# Missing export/ -> skip; the tracked-file checks always run.

root <- normalizePath(Sys.getenv("ZH_PRIVACY_ROOT", unset = repo_root), mustWork = TRUE)
has_export <- dir.exists(file.path(root, "export"))
skip_no_export <- function() skip_if_not(has_export, "export/ does not exist yet")

cfg <- yaml::read_yaml(file.path(root, "config", "export.yml"))
trackx_allowed <- c("wetter_effekt.csv", "wetter_klassen.csv", "wetter_modell.json")
trackx_csv <- function() Sys.glob(file.path(root, "export", "trackx", "*.csv"))

rel_files <- function(sub) {
  d <- file.path(root, sub)
  if (!dir.exists(d)) return(character())
  list.files(d, recursive = TRUE, all.files = TRUE, no.. = TRUE)
}

tracked_files <- function() {
  f <- system2("git", c("-c", "safe.directory=*", "-c", "core.quotepath=off", "-C", shQuote(root), "ls-files"),
               stdout = TRUE, stderr = FALSE)
  stopifnot("git ls-files returned nothing (not a repository?)" = length(f) > 0)
  f
}

# files (relative to root) whose bytes contain any of the needles; grep -a so binaries count
grep_files <- function(files, needles) {
  hits <- character()
  for (chunk in split(files, ceiling(seq_along(files) / 100))) {
    args <- c("-laF", unlist(lapply(needles, function(n) c("-e", n))), "--",
              shQuote(file.path(root, chunk)))
    r <- suppressWarnings(system2("grep", args, stdout = TRUE, stderr = FALSE))
    hits <- c(hits, substring(r, nchar(root) + 2))
  }
  hits
}

# --- 1 file allowlist ---------------------------------------------------------

allowed_export_files <- function() {
  fmts <- unlist(lapply(names(cfg$public), function(k) paste0("data/", k, ".", cfg$public[[k]]$formats)))
  c(paste0("export/", fmts),
    "export/data/unfaelle_punkte.geojson", "export/data/quartiere.geojson",
    paste0("export/trackx/", trackx_allowed))
}

test_that("every file under export/ is declared or in an allowed directory", {
  skip_no_export()
  all <- file.path("export", rel_files("export"))
  free_dirs <- grepl("^export/(modell|dq|meta)/", all)
  stray <- setdiff(all[!free_dirs], allowed_export_files())
  expect_equal(stray, character(0), info = paste("undeclared export files:", paste(stray, collapse = ", ")))
})

test_that("export.yml trackx file list matches the privacy allowlist", {
  expect_setequal(unlist(cfg$trackx$files), trackx_allowed)
  expect_gte(cfg$trackx$min_cell, 10)
})

# --- 2 column allowlist -------------------------------------------------------

parquet_cols <- function(f) {
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  DBI::dbGetQuery(con, sprintf("DESCRIBE SELECT * FROM read_parquet('%s')", f))$column_name
}

test_that("export/data CSV and Parquet columns are a subset of the allowlist", {
  skip_no_export()
  checked <- 0
  for (k in names(cfg$public)) {
    allowed <- unlist(cfg$public[[k]]$columns)
    for (fmt in cfg$public[[k]]$formats) {
      f <- file.path(root, "export", "data", paste0(k, ".", fmt))
      if (!file.exists(f)) next
      cols <- if (fmt == "csv") names(utils::read.csv(f, nrows = 1, check.names = FALSE)) else parquet_cols(f)
      extra <- setdiff(cols, allowed)
      expect_equal(extra, character(0), info = paste(basename(f), "extra columns:", paste(extra, collapse = ", ")))
      checked <- checked + 1
    }
  }
  skip_if(checked == 0, "no export/data files yet")
})

# The map layer deliberately carries fewer attributes than the table (no month/weekday/hour):
# jahr, schwere, velo, fussgaenger, motorrad - under short aliases (see R/export.R).
test_that("point GeoJSON carries only the minimal map attributes", {
  skip_no_export()
  f <- file.path(root, "export", "data", "unfaelle_punkte.geojson")
  skip_if_not(file.exists(f), "no unfaelle_punkte.geojson yet")
  gj <- jsonlite::read_json(f)
  props <- unique(unlist(lapply(gj$features, function(x) names(x$properties))))
  expect_equal(setdiff(props, c("j", "s", "v", "f", "m")), character(0))
})

# --- 3 forbidden strings in published/tracked content ---------------------------

scan_candidates <- function() {
  f <- tracked_files()
  if (has_export) f <- c(f, file.path("export", rel_files("export")))
  if (dir.exists(file.path(root, "site", "_site"))) f <- c(f, file.path("site", "_site", rel_files("site/_site")))
  f <- unique(f)
  f <- f[file.exists(file.path(root, f))]
  # code/docs legitimately name the columns; they never hold data
  f[!grepl("^(R|sql|tests|tools|docs)/|\\.(md|qmd)$", f)]
}

test_that("no tracked/exported/built file contains an exact-timestamp column name", {
  hits <- grep_files(scan_candidates(), c("timestampOriginal", "ts_lokal"))
  expect_equal(hits, character(0), info = paste("leaking:", paste(hits, collapse = ", ")))
})

test_that("no tracked file is the private source file (sha256)", {
  src <- readLines(file.path(root, "tools", "privacy-precommit.sh"), warn = FALSE)
  sha <- sub('.*PRIVATE_SHA256="([0-9a-f]{64})".*', "\\1", grep("^PRIVATE_SHA256=", src, value = TRUE))
  expect_match(sha, "^[0-9a-f]{64}$")
  f <- tracked_files()
  f <- f[file.exists(file.path(root, f))]
  sums <- character()
  for (chunk in split(f, ceiling(seq_along(f) / 100))) {
    out <- system2("sha256sum", shQuote(file.path(root, chunk)), stdout = TRUE)
    sums <- c(sums, sub(" .*", "", out))
  }
  expect_false(sha %in% sums)
  expect_false(any(grepl("unfaelle.*\\.csv$|\\.duckdb$", basename(f)) & !grepl("^export/", f)),
               info = "private-looking file name is tracked")
})

# --- 4 Track X outputs -----------------------------------------------------------

test_that("wetter_klassen.csv: fixed columns, every cell has >= 10 accidents and >= 10 hours", {
  f <- file.path(root, "export", "trackx", "wetter_klassen.csv")
  skip_if_not(file.exists(f), "no wetter_klassen.csv yet")
  d <- utils::read.csv(f, check.names = FALSE)
  expect_identical(names(d), c("regen", "temperatur", "stunden", "unfaelle", "unfaelle_pro_stunde"))
  expect_gt(nrow(d), 0)
  expect_true(all(d$unfaelle >= 10), info = "cell with < 10 accidents")
  expect_true(all(d$stunden >= 10), info = "cell with < 10 hours")
})

test_that("Track X CSVs contain no dates and no date-like column names", {
  fs <- trackx_csv()
  skip_if(length(fs) == 0, "no Track X CSVs yet")
  for (f in fs) {
    txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
    expect_false(grepl("\\d{4}-\\d{2}-\\d{2}", txt), info = paste(basename(f), "contains an ISO date"))
    expect_false(grepl("\\d{1,2}\\.\\d{1,2}\\.\\d{4}", txt), info = paste(basename(f), "contains a dd.mm.yyyy date"))
    cols <- tolower(names(utils::read.csv(f, nrows = 1, check.names = FALSE)))
    bad <- cols[grepl("date|datum|(^|_)ts($|_)|tag|woche|week|day", cols)]
    expect_equal(bad, character(0), info = paste(basename(f), "date-like columns:", paste(bad, collapse = ", ")))
  }
})

# JOIN ATTACK. The public accident rows carry (jahr, monat, wochentag, stunde, quartier, lon/lat).
# If a Track X output carried any of these as a column, it could be joined to public rows, and an
# attribute that is private-only (exact day, weather of that hour) would pin down the exact date.
# Track X is therefore allowed to be keyed ONLY by coarse weather bins (rain x temperature),
# which are shared by thousands of hours and carry no join path into the public rows.
test_that("JOIN-ATTACK: Track X CSVs have no column that keys to public row attributes", {
  fs <- trackx_csv()
  skip_if(length(fs) == 0, "no Track X CSVs yet")
  join_keys <- c("jahr", "monat", "wochentag", "stunde", "datum", "unfall_id", "lon", "lat", "quartier")
  for (f in fs) {
    cols <- tolower(names(utils::read.csv(f, nrows = 1, check.names = FALSE)))
    hit <- intersect(cols, join_keys)
    expect_equal(hit, character(0), info = paste(basename(f), "has join keys:", paste(hit, collapse = ", ")))
    expect_false(any(grepl("^(quartier|kreis)", cols)), info = paste(basename(f), "has spatial key"))
  }
})

test_that("Track X JSON: no dates, no serialized model objects", {
  f <- file.path(root, "export", "trackx", "wetter_modell.json")
  skip_if_not(file.exists(f), "no wetter_modell.json yet")
  txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
  expect_false(grepl("\\d{4}-\\d{2}-\\d{2}", txt))
  expect_lt(file.size(f), 100 * 1024)       # coefficients, not a fitted object holding training rows
  expect_false(grepl("\"(data|model|residuals|fitted\\.values|y|x)\"\\s*:\\s*\\[", txt))
  expect_no_error(jsonlite::fromJSON(txt))
})
