# Pipeline definition: government data -> warehouse -> quality gate -> insight.
# Run: make run   (or: Rscript -e 'targets::tar_make()')
library(targets)
library(tarchetypes)

tar_option_set(packages = c("DBI", "duckdb"), format = "rds")
tar_source("R")

list(
  # --- configuration -------------------------------------------------------
  tar_target(cfg_file, "config/sources.yml", format = "file"),
  tar_target(cfg, yaml::read_yaml(cfg_file)),
  tar_target(snapshot_date, as.character(Sys.Date()), cue = tar_cue(mode = "always")),

  # --- 1 ingest: official APIs -> dated snapshot + manifest -----------------
  tar_target(manifest, fetch_all(cfg, snapshot_date)),

  # --- 2 warehouse: raw -> staging -> mart (SQL) ----------------------------
  tar_files_input(sql_files, list.files(c("sql/raw", "sql/staging", "sql/mart"), "\\.sql$", full.names = TRUE)),
  tar_target(
    warehouse,
    build_warehouse(manifest, cfg, sql_files, "data/warehouse.duckdb",
                    private_path = Sys.getenv("ZH_PRIVATE_ACCIDENTS")),
    format = "file"
  ),

  # --- 3 data quality: contracts + SQL checks + history -> gate -------------
  tar_files_input(dq_check_files, list.files("sql/dq", "\\.sql$", full.names = TRUE)),
  tar_files_input(dq_contract_files, list.files("dq/contracts", "\\.yml$", full.names = TRUE)),
  tar_target(
    dq_results,
    run_dq(warehouse, manifest, cfg, dq_check_files, dq_contract_files,
           history_file = "export/dq/snapshot_history.csv",
           report_dir = "export/dq")
  ),
  tar_target(dq_passed, dq_gate(dq_results))
)
