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
  tar_target(dq_passed, dq_gate(dq_results)),

  # --- 4 models (only after the STOP gate) ----------------------------------
  tar_files_input(export_cfg_file, "config/export.yml"),
  tar_files_input(codebook_file, "config/codebook.yml"),
  tar_target(export_cfg, yaml::read_yaml(export_cfg_file)),
  # Track X: NULL when the private file is absent (CI / public track only).
  tar_target(weather_model, {
    dq_passed
    fit_weather(warehouse)
  }),
  tar_target(severity_model, {
    dq_passed
    fit_severity(warehouse)
  }),

  # --- 5 export: the only path to the public (all behind dq_passed) ---------
  tar_target(export_public_files, {
    dq_passed
    export_public(warehouse, export_cfg)
  }, format = "file"),
  tar_target(export_model_files, {
    dq_passed
    export_models(severity_model)
  }, format = "file"),
  tar_target(export_trackx_files, {
    dq_passed
    export_trackx(weather_model, export_cfg)
  }, format = "file"),
  tar_target(export_dq_files, {
    dq_passed
    export_dq(dq_results, manifest)
  }, format = "file"),
  tar_target(dictionary_file, {
    dq_passed
    build_dictionary(export_cfg, codebook_file)
  }, format = "file"),
  tar_target(dcat_file, {
    dq_passed
    build_dcat(export_cfg, cfg, export_public_files,
               site_url = "https://ffahrenb.github.io/zurich-road-accidents/")
  }, format = "file")
)
