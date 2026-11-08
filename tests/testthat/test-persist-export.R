# tools/persist-export.sh (CI job `persist`) against a local bare origin: artifact verification,
# export/-only commits, Track X untouched, main-moved and push-race handling.
test_that("persist-export.sh behaves as specified (offline, local bare repo)", {
  skip_if(Sys.which("git") == "" || Sys.which("sha256sum") == "", "git / sha256sum not available")
  out <- suppressWarnings(system2("bash", file.path(repo_root, "tests", "persist-export-test.sh"),
                                  stdout = TRUE, stderr = TRUE))
  status <- attr(out, "status")
  expect_true(is.null(status) || status == 0, info = paste(out, collapse = "\n"))
  expect_true("ALL OK" %in% out, info = paste(out, collapse = "\n"))
})
