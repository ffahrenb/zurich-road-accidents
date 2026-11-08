# Lint all R code with the repo's .lintr; exit non-zero on any finding.
# Usage (repo root): Rscript tests/lint.R
files <- c(list.files(c("R", "tests"), "\\.R$", recursive = TRUE, full.names = TRUE), "_targets.R")
files <- files[file.exists(files)]
lints <- do.call(c, lapply(files, lintr::lint))
if (length(lints)) {
  print(lints)
  quit(status = 1)
}
cat("lintr: ", length(files), " files clean\n", sep = "")
