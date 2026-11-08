# Runner: Rscript tests/testthat.R   (from the repo root)
library(testthat)
test_dir("tests/testthat", reporter = "summary", stop_on_failure = TRUE)
