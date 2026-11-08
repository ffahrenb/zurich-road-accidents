# PRIVACY SCAN OF THE BUILT SITE (site/_site). Run after `quarto render site/` (CI does, after "Render site").
# Unlike the tracked-file scan in test-privacy.R, nothing is exempt here: the published site must not
# carry the private file, exact-timestamp column names or references to the private workspace.
# Skipped when site/_site does not exist. Root override: ZH_PRIVACY_ROOT (as in test-privacy.R).

priv_root <- normalizePath(Sys.getenv("ZH_PRIVACY_ROOT", unset = repo_root), mustWork = TRUE)
site_root <- file.path(priv_root, "site", "_site")

site_files <- function() {
  skip_if_not(dir.exists(site_root), "site/_site does not exist (render the site first)")
  f <- list.files(site_root, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  expect_gt(length(f), 0)
  f
}

# files (relative to site_root) containing any needle; grep -a so binaries are scanned too
site_grep <- function(files, needles, ignore_case = FALSE) {
  hits <- character()
  flags <- paste0("-la", if (ignore_case) "i", "F")
  for (chunk in split(files, ceiling(seq_along(files) / 100))) {
    args <- c(flags, unlist(lapply(needles, function(n) c("-e", n))), "--",
              shQuote(file.path(site_root, chunk)))
    r <- suppressWarnings(system2("grep", args, stdout = TRUE, stderr = FALSE))
    hits <- c(hits, substring(r, nchar(site_root) + 2))
  }
  hits
}

test_that("_site holds no private-looking file name (*unfaelle*.csv, *.duckdb)", {
  f <- site_files()
  bad <- f[grepl("unfaelle.*\\.csv$|\\.duckdb$", basename(f), ignore.case = TRUE)]
  expect_equal(bad, character(0), info = paste("private-looking files:", paste(bad, collapse = ", ")))
})

test_that("_site contains no exact-timestamp column name", {
  hits <- site_grep(site_files(), c("timestampOriginal", "ts_lokal"))
  expect_equal(hits, character(0), info = paste("leaking:", paste(hits, collapse = ", ")))
})

# Forbidden strings (names of non-public workspaces) live in an untracked file,
# one per line, so the public repo never names them. Skipped when absent (CI).
test_that("_site references no non-public workspace", {
  deny_file <- file.path(priv_root, "private", "forbidden_strings.txt")
  skip_if_not(file.exists(deny_file), "private/forbidden_strings.txt not present")
  deny <- trimws(readLines(deny_file, warn = FALSE))
  deny <- deny[nzchar(deny)]
  hits <- site_grep(site_files(), deny, ignore_case = TRUE)
  expect_equal(hits, character(0), info = paste("references in:", paste(hits, collapse = ", ")))
})

test_that("no file in _site is the private source file (sha256)", {
  f <- site_files()
  src <- readLines(file.path(priv_root, "tools", "privacy-precommit.sh"), warn = FALSE)
  sha <- sub('.*PRIVATE_SHA256="([0-9a-f]{64})".*', "\\1", grep("^PRIVATE_SHA256=", src, value = TRUE))
  expect_match(sha, "^[0-9a-f]{64}$")
  sums <- character()
  for (chunk in split(f, ceiling(seq_along(f) / 100))) {
    out <- system2("sha256sum", shQuote(file.path(site_root, chunk)), stdout = TRUE)
    sums <- c(sums, sub(" .*", "", out))
  }
  expect_equal(length(sums), length(f))
  expect_false(sha %in% sums)
})
