# Proves the privacy gate itself works: it must PASS a good tree and FAIL each bad one.
# Fake trees are built in tempdirs at test time (nothing is committed).

point_json <- function(props) {
  p <- paste(sprintf('"%s": 1', props), collapse = ", ")
  sprintf('{"type": "FeatureCollection", "features": [{"type": "Feature", "properties": {%s}, "geometry": null}]}', p)
}

write_csv <- function(path, d) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(d, path, row.names = FALSE)
}

# A minimal tree that satisfies every privacy rule. `mutate(root)` then breaks one thing.
make_tree <- function(mutate = function(root) NULL, with_export = TRUE) {
  root <- withr::local_tempdir(.local_envir = parent.frame())
  dir.create(file.path(root, "config"))
  dir.create(file.path(root, "tools"))
  file.copy(file.path(repo_root, "config", "export.yml"), file.path(root, "config", "export.yml"))
  file.copy(file.path(repo_root, "tools", "privacy-precommit.sh"), file.path(root, "tools", "privacy-precommit.sh"))
  writeLines("# project", file.path(root, "notes.txt"))
  if (with_export) {
    write_csv(file.path(root, "export/data/jahr.csv"),
              data.frame(jahr = 2020, schwere_kurz = "leicht", unfaelle = 5, mit_velo = 1,
                         mit_fussgaenger = 0, mit_motorrad = 0))
    write_csv(file.path(root, "export/trackx/wetter_klassen.csv"),
              data.frame(regen = "trocken", temperatur = "10-20", stunden = 500, unfaelle = 40,
                         unfaelle_pro_stunde = 0.08))
    write_csv(file.path(root, "export/trackx/wetter_effekt.csv"),
              data.frame(term = "regen", schaetzer = 0.31, se = 0.05))
    writeLines('{"koeffizienten": {"regen": 0.31}}', file.path(root, "export/trackx/wetter_modell.json"))
    write_csv(file.path(root, "export/dq/snapshot_history.csv"), data.frame(jahr = 2020, n = 1, snapshot = "x"))
    writeLines(point_json("j"), file.path(root, "export/data/unfaelle_punkte.geojson"))
  }
  mutate(root)
  system2("git", c("-C", shQuote(root), "init", "-q"))
  system2("git", c("-C", shQuote(root), "add", "-A"))
  root
}

# Run test-privacy.R against a tree; return failure/skip counts.
gate <- function(root) {
  withr::local_envvar(ZH_PRIVACY_ROOT = root)
  res <- as.data.frame(testthat::test_file(testthat::test_path("test-privacy.R"), reporter = "silent",
                                           stop_on_failure = FALSE))
  list(failed = sum(res$failed) + sum(res$error), skipped = sum(res$skipped), passed = sum(res$passed))
}

test_that("good tree passes the privacy gate", {
  g <- gate(make_tree())
  expect_equal(g$failed, 0)
  expect_gt(g$passed, 10)
})

test_that("missing export/ skips export tests but the tracked-file checks still run", {
  g <- gate(make_tree(with_export = FALSE))
  expect_equal(g$failed, 0)
  expect_gt(g$skipped, 0)
  expect_gt(g$passed, 0)     # sha256 + string scan + config checks executed
})

# Each case writes one deliberately bad file into the otherwise good tree.
klassen <- function(...) {
  function(r) write_csv(file.path(r, "export/trackx/wetter_klassen.csv"), data.frame(regen = "nass", ...))
}
effekt <- function(d) function(r) write_csv(file.path(r, "export/trackx/wetter_effekt.csv"), d)
put <- function(path, txt) {
  function(r) {
    dir.create(dirname(file.path(r, path)), recursive = TRUE, showWarnings = FALSE)
    writeLines(txt, file.path(r, path))
  }
}

jahr_cols <- list(jahr = 2020, schwere_kurz = "x", unfaelle = 1, mit_velo = 1, mit_fussgaenger = 0, mit_motorrad = 0)

bad_cases <- list(
  "stray file in export/" = put("export/rohdaten.txt", "x"),
  "undeclared file in export/data" = put("export/data/geheim.csv", "a"),
  "undeclared trackx file" = put("export/trackx/stunden.csv", "a"),
  "hour attribute on the map points" =
    put("export/data/unfaelle_punkte.geojson", point_json(c("j", "stunde"))),
  "extra column in public CSV" = function(r) {
    write_csv(file.path(r, "export/data/jahr.csv"), do.call(data.frame, c(jahr_cols, list(ts_exakt = "x"))))
  },
  "tracked file names timestampOriginal" = put("notes.txt", "col timestampOriginal"),
  "exported file names ts_lokal" = put("export/meta/x.csv", "ts_lokal"),
  "tracked file has the private sha" = function(r) {
    writeLines("pretend private data", file.path(r, "private_copy.dat"))
    sha <- sub(" .*", "", system2("sha256sum", shQuote(file.path(r, "private_copy.dat")), stdout = TRUE))
    p <- file.path(r, "tools/privacy-precommit.sh")
    writeLines(sub('PRIVATE_SHA256="[0-9a-f]+"', sprintf('PRIVATE_SHA256="%s"', sha), readLines(p)), p)
  },
  "klassen cell with < 10 accidents" =
    klassen(temperatur = "0-5", stunden = 50, unfaelle = 3, unfaelle_pro_stunde = 0.06),
  "klassen cell with < 10 hours" =
    klassen(temperatur = "0-5", stunden = 4, unfaelle = 20, unfaelle_pro_stunde = 5),
  "klassen wrong columns" = klassen(temperatur = "0-5", stunden = 40, unfaelle = 20),
  "date string in trackx csv" = effekt(data.frame(term = "2021-03-14", schaetzer = 1, se = 1)),
  "date-like column in trackx csv" = effekt(data.frame(term = "regen", datum = 1, se = 1)),
  "join key column in trackx csv" = effekt(data.frame(term = "regen", stunde = 14, schaetzer = 1)),
  "date in trackx json" = put("export/trackx/wetter_modell.json", '{"fit_am": "2021-03-14"}')
)

for (nm in names(bad_cases)) {
  test_that(paste("privacy gate FAILS closed:", nm), {
    g <- gate(make_tree(bad_cases[[nm]]))
    expect_gt(g$failed, 0)
  })
}
