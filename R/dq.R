# Data-quality engine.
#  1. Contracts (dq/contracts/*.yml) -> {pointblank} agents, HTML report per source
#  2. SQL checks (sql/dq/*.sql)       -> metadata in the file header
#  3. History checks in R             -> snapshot deltas, source freshness
# Every check yields one row in dq_results. STOP failures halt the pipeline.

parse_check_header <- function(path) {
  lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
  hdr <- regmatches(lines, regexec("^-- ([a-z_]+): (.*)$", lines))
  hdr <- Filter(length, hdr)
  meta <- stats::setNames(lapply(hdr, `[[`, 3), vapply(hdr, `[[`, "", 2))
  meta$file <- path
  meta
}

check_status <- function(n_tested, n_failed, severity, tolerance_pct) {
  if (is.na(n_failed)) return(severity)          # a check that cannot run is not a pass
  if (is.na(tolerance_pct)) tolerance_pct <- 0
  if (n_failed == 0) return("PASS")
  pct <- if (is.na(n_tested) || n_tested == 0) 100 else 100 * n_failed / n_tested
  if (pct <= tolerance_pct) "PASS" else severity
}

result_row <- function(id, quelle, dimension, schwere, titel_de, titel_en,
                       n_tested, n_failed, tol, detail = NA_character_, art = "SQL") {
  data.frame(
    check_id = id, art = art, quelle = quelle, dimension = dimension,
    schwere = schwere, titel_de = titel_de, titel_en = titel_en,
    n_tested = as.numeric(n_tested), n_failed = as.numeric(n_failed),
    toleranz_pct = tol,
    status = check_status(n_tested, n_failed, schwere, tol),
    detail = detail, stringsAsFactors = FALSE
  )
}

run_sql_checks <- function(con, files, params) {
  tables <- DBI::dbListTables(con)
  rows <- lapply(sort(files), function(f) {
    m <- parse_check_header(f)
    if (!is.null(m$benoetigt) && !(m$benoetigt %in% tables)) return(NULL)
    sql <- render_sql(paste(readLines(f, warn = FALSE, encoding = "UTF-8"), collapse = "\n"), params)
    r <- DBI::dbGetQuery(con, sub(";\\s*$", "", sql))
    tol <- if (is.null(m$toleranz_pct)) 0 else as.numeric(m$toleranz_pct)
    result_row(m$id, m$quelle, m$dimension, m$schwere, m$titel_de, m$titel_en,
               r$n_tested, r$n_failed, tol,
               if ("detail" %in% names(r)) as.character(r$detail) else NA_character_)
  })
  do.call(rbind, rows)
}

run_contracts <- function(con, files, report_dir) {
  dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)
  rows <- lapply(sort(files), function(f) {
    ct <- yaml::read_yaml(f)
    tbl <- dplyr::tbl(con, ct$table)
    present <- colnames(tbl)
    agent <- pointblank::create_agent(
      tbl = tbl, tbl_name = ct$table,
      label = paste("Datenvertrag", ct$quelle),
      actions = pointblank::action_levels(warn_at = 1)
    )
    for (col in ct$columns) {
      agent <- pointblank::col_exists(agent, columns = col$name)
      if (!col$name %in% present) next
      if (isTRUE(col$not_null)) agent <- pointblank::col_vals_not_null(agent, columns = col$name)
      if (!is.null(col$in_set)) {
        agent <- pointblank::col_vals_in_set(agent, columns = col$name, set = unlist(col$in_set))
      }
      if (!is.null(col$between)) {
        agent <- pointblank::col_vals_between(agent, columns = col$name,
                                              left = col$between[[1]], right = col$between[[2]])
      }
    }
    agent <- pointblank::interrogate(agent, progress = FALSE)
    pointblank::export_report(agent, quiet = TRUE,
                              filename = file.path(report_dir, paste0("vertrag_", ct$quelle, ".html")))
    vs <- agent$validation_set
    n_steps <- nrow(vs)
    failed_steps <- vs[!vs$all_passed %in% TRUE, ]
    detail <- if (nrow(failed_steps)) {
      paste(sprintf("%s(%s): %s Fehler", failed_steps$assertion_type,
                    vapply(failed_steps$column, function(x) paste(unlist(x), collapse = ","), ""),
                    failed_steps$n_failed), collapse = "; ")
    } else {
      NA_character_
    }
    result_row(
      paste0("DQ-C-", toupper(substr(ct$quelle, 1, 3))), ct$quelle, "Schema & Vertrag", ct$schwere,
      paste0("Datenvertrag eingehalten: Spalten, Pflichtfelder, Wertelisten (", n_steps, " Regeln)"),
      paste0("Data contract met: columns, mandatory fields, value lists (", n_steps, " rules)"),
      n_steps, nrow(failed_steps), 0, detail, art = "pointblank"
    )
  })
  do.call(rbind, rows)
}

# Compares per-year accident counts with the previous snapshot.
# A publisher silently deleting or rewriting history is caught here.
check_snapshot_delta <- function(con, history_file, snapshot_date) {
  cur <- DBI::dbGetQuery(con, paste(
    "SELECT AccidentYear::INTEGER AS jahr, count(*)::INTEGER AS n",
    "FROM raw_unfaelle GROUP BY 1 ORDER BY 1"))
  cur$snapshot <- as.character(snapshot_date)
  hist <- if (file.exists(history_file)) utils::read.csv(history_file, stringsAsFactors = FALSE) else cur[0, ]
  # Reference = latest entry dated strictly before today's snapshot. Re-running the same snapshot
  # date neither becomes its own reference nor appends a second block of rows.
  prev_dates <- unique(hist$snapshot)
  prev_dates <- prev_dates[prev_dates < cur$snapshot[1]]
  detail <- NA_character_
  n_failed <- 0
  n_tested <- nrow(cur)
  if (length(prev_dates)) {
    prev <- hist[hist$snapshot == max(prev_dates), c("jahr", "n")]
    cmp <- merge(prev, cur[, c("jahr", "n")], by = "jahr", suffixes = c("_vorher", "_jetzt"))
    cmp$delta <- cmp$n_jetzt / cmp$n_vorher - 1
    bad <- cmp[abs(cmp$delta) > 0.01, ]
    n_failed <- nrow(bad)
    n_tested <- nrow(cmp)
    if (n_failed) detail <- paste(sprintf("%d: %+.1f %%", bad$jahr, 100 * bad$delta), collapse = "; ")
  } else {
    detail <- "erster Snapshot – Referenz angelegt"
  }
  # same date = overwrite, never duplicate
  keep <- c("jahr", "n", "snapshot")
  hist <- rbind(hist[hist$snapshot != cur$snapshot[1], keep], cur[, keep])
  dir.create(dirname(history_file), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(hist, history_file, row.names = FALSE)
  # >10 % shrink of total history = STOP (the 2023 "180k -> 55k" case)
  total_drop <- if (length(prev_dates)) {
    1 - sum(cur$n) / sum(hist$n[hist$snapshot == max(prev_dates)])
  } else {
    0
  }
  rbind(
    result_row("DQ-S01", "unfaelle", "Stabilität", "WARN",
               "Unfallzahlen je Jahr weichen höchstens 1 % vom letzten Snapshot ab",
               "Accident counts per year deviate at most 1 % from the previous snapshot",
               n_tested, n_failed, 0, detail, art = "Historie"),
    result_row("DQ-S02", "unfaelle", "Stabilität", "STOP",
               "Datenbestand ist gegenüber dem letzten Snapshot nicht um mehr als 10 % geschrumpft",
               "Dataset has not shrunk by more than 10 % since the previous snapshot",
               1, as.integer(total_drop > 0.10), 0,
               sprintf("Veränderung gesamt: %+.1f %%", -100 * total_drop), art = "Historie")
  )
}

check_freshness <- function(manifest, cfg) {
  src <- unique(manifest[, c("source", "source_modified")])
  rows <- lapply(seq_len(nrow(src)), function(i) {
    key <- src$source[i]
    mod <- as.Date(substr(src$source_modified[i], 1, 10))
    age <- as.numeric(Sys.Date() - mod)
    cad <- cfg$sources[[key]]$cadence_days
    result_row(paste0("DQ-F-", toupper(substr(key, 1, 3))), key, "Aktualität", "WARN",
               paste0("Quelle wurde im erwarteten Rhythmus aktualisiert (≤ ", cad, " Tage)"),
               paste0("Source updated within expected cadence (≤ ", cad, " days)"),
               1, as.integer(age > cad), 0, sprintf("letzte Änderung %s (%d Tage)", mod, round(age)),
               art = "Metadaten")
  })
  do.call(rbind, rows)
}

run_dq <- function(db_path, manifest, cfg, check_files, contract_files, history_file, report_dir) {
  con <- db_connect(db_path, read_only = TRUE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  params <- list(year_from = cfg$years$from, year_to = cfg$years$to, station = cfg$params$station)
  snapshot_date <- max(as.Date(substr(manifest$retrieved_utc, 1, 10)))
  res <- rbind(
    run_contracts(con, contract_files, report_dir),
    run_sql_checks(con, check_files, params),
    check_snapshot_delta(con, history_file, snapshot_date),
    check_freshness(manifest, cfg)
  )
  res$run_utc <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  res$snapshot <- as.character(snapshot_date)
  res
}

# The release gate: refuses to continue when any STOP check failed.
dq_gate <- function(dq_results) {
  # NA status counts as failing at the check's own severity (STOP if that is unknown too)
  sev <- if ("schwere" %in% names(dq_results)) dq_results$schwere else rep(NA_character_, nrow(dq_results))
  sev[is.na(sev)] <- "STOP"
  eff <- ifelse(is.na(dq_results$status), sev, dq_results$status)
  stops <- dq_results[eff == "STOP", , drop = FALSE]
  if (nrow(stops)) {
    stop("Datenqualität: ", nrow(stops), " STOP-Prüfung(en) verletzt – keine Veröffentlichung.\n",
         paste(sprintf("  %s %s (%s)", stops$check_id, stops$titel_de, stops$detail), collapse = "\n"),
         call. = FALSE)
  }
  invisible(TRUE)
}
