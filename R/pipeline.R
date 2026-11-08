# Build the warehouse from a snapshot manifest: raw -> staging -> mart.

files_of <- function(manifest, key) {
  sql_list(manifest$path[manifest$source == key])
}

build_warehouse <- function(manifest, cfg, sql_files, db_path, private_path = "") {
  if (file.exists(db_path)) file.remove(db_path)
  con <- db_connect(db_path)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

  p <- cfg$params
  params <- list(
    unfaelle = files_of(manifest, "unfaelle"),
    meteo = files_of(manifest, "meteo"),
    luft = files_of(manifest, "luft"),
    bevoelkerung = files_of(manifest, "bevoelkerung"),
    quartiere = sprintf("'%s'", manifest$path[manifest$source == "quartiere"]),
    schulen = sprintf("'%s'", manifest$path[manifest$source == "schulen"]),
    tempo = sprintf("'%s'", manifest$path[manifest$source == "tempo"]),
    year_from = cfg$years$from,
    year_to = cfg$years$to,
    school_radius_m = p$school_radius_m,
    tempo_radius_m = p$tempo_radius_m,
    station = p$station,
    x_from = p$x_from,
    x_to = p$x_to
  )

  layer <- match(basename(dirname(sql_files)), c("raw", "staging", "mart"))
  sql_files <- sql_files[order(layer, basename(sql_files))]
  public <- sql_files[!grepl("trackx", sql_files)]
  for (f in public) run_sql_file(con, f, params)

  has_x <- load_private(con, private_path)
  if (has_x) {
    for (f in sql_files[grepl("trackx", sql_files)]) run_sql_file(con, f, params)
  }
  db_path
}
