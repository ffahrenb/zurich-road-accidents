# DuckDB helpers. All transformation logic lives in sql/*.sql; R only
# injects parameters and runs the files in order.

db_connect <- function(path, read_only = FALSE) {
  con <- DBI::dbConnect(
    duckdb::duckdb(),
    dbdir = path,
    read_only = read_only,
    config = list(
      extension_directory = Sys.getenv("DUCKDB_EXTENSION_DIR", "/opt/duckdb_extensions"),
      autoinstall_known_extensions = "false",
      autoload_known_extensions = "false"
    )
  )
  DBI::dbExecute(con, "LOAD spatial")
  DBI::dbExecute(con, "LOAD icu")
  DBI::dbExecute(con, "SET TimeZone = 'UTC'")
  con
}

sql_list <- function(paths) {
  paste0("[", paste0("'", paths, "'", collapse = ", "), "]")
}

# Replace {{name}} placeholders; fail loudly if one is left unfilled.
render_sql <- function(sql, params) {
  for (nm in names(params)) {
    sql <- gsub(paste0("{{", nm, "}}"), params[[nm]], sql, fixed = TRUE)
  }
  left <- regmatches(sql, gregexpr("\\{\\{[a-z_]+\\}\\}", sql))[[1]]
  if (length(left)) stop("unfilled SQL parameter(s): ", paste(unique(left), collapse = ", "))
  sql
}

# Split a file into statements on ';' at line end and execute them in order.
run_sql_file <- function(con, path, params = list()) {
  sql <- render_sql(paste(readLines(path, warn = FALSE), collapse = "\n"), params)
  stmts <- strsplit(sql, ";\\s*(\n|$)")[[1]]
  stmts <- stmts[nzchar(trimws(gsub("--[^\n]*", "", stmts)))]
  for (s in stmts) DBI::dbExecute(con, s)
  invisible(path)
}

# Load the private exact-date file (Track X). Only two columns are read:
# the accident id and the exact timestamp. Returns FALSE if not configured.
load_private <- function(con, path) {
  if (!nzchar(path) || !file.exists(path)) return(FALSE)
  x <- utils::read.csv(path, fileEncoding = "latin1", colClasses = "character")
  x <- x[, c("AccidentUID", "timestampOriginal")]
  DBI::dbWriteTable(con, "raw_x_private", x, overwrite = TRUE)
  TRUE
}
