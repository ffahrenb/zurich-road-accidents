# Export layer: the ONLY path from the warehouse to the public.
# Column allowlist: config/export.yml. Formats: CSV + Parquet (+ GeoJSON for maps).

export_public <- function(db_path, export_cfg, out_dir = "export/data") {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  con <- db_connect(db_path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  files <- character()
  for (key in names(export_cfg$public)) {
    e <- export_cfg$public[[key]]
    sel <- sprintf("SELECT %s FROM %s ORDER BY ALL", paste(e$columns, collapse = ", "), e$table)
    for (fmt in e$formats) {
      path <- file.path(out_dir, paste0(key, ".", fmt))
      opt <- if (fmt == "csv") "(FORMAT csv, HEADER true)" else "(FORMAT parquet, COMPRESSION zstd)"
      DBI::dbExecute(con, sprintf("COPY (%s) TO '%s' %s", sel, path, opt))
      files <- c(files, path)
    }
  }
  # Map layers (WGS84, rounded to ~1 m).
  pts <- file.path(out_dir, "unfaelle_punkte.geojson")
  DBI::dbExecute(con, sprintf("
    COPY (
      SELECT jahr AS j,
             CASE schwere_kurz WHEN 'Sachschaden' THEN 0 WHEN 'Leichtverletzte' THEN 1
                               WHEN 'Schwerverletzte' THEN 2 ELSE 3 END AS s,
             mit_velo::INT AS v, mit_fussgaenger::INT AS f, mit_motorrad::INT AS m,
             st_point(round(lon, 5), round(lat, 5)) AS geom
      FROM mart_unfaelle
    ) TO '%s' WITH (FORMAT gdal, DRIVER 'GeoJSON', LAYER_CREATION_OPTIONS 'COORDINATE_PRECISION=5')", pts))
  qrt <- file.path(out_dir, "quartiere.geojson")
  DBI::dbExecute(con, sprintf("
    COPY (
      SELECT q.quartier_nr, q.quartier, q.kreis_nr,
             round(avg(m.personenschaden_pro_1000), 2) AS rate,
             sum(m.mit_personenschaden) AS personenschaden,
             st_transform(st_simplifypreservetopology(q.geom, 15), 'EPSG:2056', 'EPSG:4326', always_xy := TRUE) AS geom
      FROM stg_quartiere q
      LEFT JOIN mart_quartier m ON q.quartier_nr = m.quartier_nr AND m.jahr >= 2015
      GROUP BY ALL
    ) TO '%s' WITH (FORMAT gdal, DRIVER 'GeoJSON', LAYER_CREATION_OPTIONS 'COORDINATE_PRECISION=5')", qrt))
  c(files, pts, qrt)
}

write_csv <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(x, path, row.names = FALSE, na = "", fileEncoding = "UTF-8")
  path
}

export_models <- function(sev, out_dir = "export/modell") {
  c(
    write_csv(sev$metrics, file.path(out_dir, "schwere_metriken.csv")),
    write_csv(sev$calibration, file.path(out_dir, "schwere_kalibrierung.csv")),
    write_csv(sev$odds_ratios, file.path(out_dir, "schwere_odds_ratios.csv")),
    write_csv(sev$importance, file.path(out_dir, "schwere_wichtigkeit.csv"))
  )
}

# Track X: statistical disclosure control before anything is written.
export_trackx <- function(wx, export_cfg, out_dir = "export/trackx") {
  if (is.null(wx)) return(character())
  k <- export_cfg$trackx$min_cell
  bins <- wx$bins
  bins <- bins[bins$unfaelle >= k & bins$stunden >= k, ]        # suppress small cells
  bins <- bins[, c("regen", "temperatur", "stunden", "unfaelle", "unfaelle_pro_stunde")]
  meta <- list(
    modell = "Negative Binomial-Regression (MASS::glm.nb)",
    formel = "Unfälle pro Stunde ~ Regen + Temperaturklasse + Stunde×Wochenende + Monat + Jahr",
    zeitraum = paste(wx$period, collapse = "–"),
    n_stunden = wx$n_hours,
    referenzstation = "Zch_Stampfenbachstrasse",
    datenschutz = sprintf("Nur Modellkoeffizienten und Klassen mit mindestens %d Fällen; keine Einzeldaten, keine Datumsangaben.", k)
  )
  c(
    write_csv(wx$irr, file.path(out_dir, "wetter_effekt.csv")),
    write_csv(bins, file.path(out_dir, "wetter_klassen.csv")),
    { p <- file.path(out_dir, "wetter_modell.json"); jsonlite::write_json(meta, p, auto_unbox = TRUE, pretty = TRUE); p }
  )
}

export_dq <- function(dq_results, manifest, out_dir = "export/dq") {
  hist_file <- file.path(out_dir, "dq_verlauf.csv")
  hist <- if (file.exists(hist_file)) utils::read.csv(hist_file, stringsAsFactors = FALSE) else NULL
  cols <- c("run_utc", "snapshot", "check_id", "status", "n_tested", "n_failed")
  hist <- rbind(hist[, cols, drop = FALSE], dq_results[, cols])
  hist <- hist[!duplicated(hist[, c("snapshot", "check_id")], fromLast = TRUE), ]
  pub_manifest <- manifest[, c("source", "file", "bytes", "sha256", "source_modified", "retrieved_utc", "licence")]
  c(
    write_csv(dq_results, file.path(out_dir, "dq_ergebnisse.csv")),
    write_csv(hist, hist_file),
    write_csv(pub_manifest, file.path(out_dir, "manifest.csv"))
  )
}
