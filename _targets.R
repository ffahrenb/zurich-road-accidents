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
  # resolved year range (years.to = auto): everything downstream uses cfg_run, never cfg$years
  tar_target(years_info, read_years(manifest)),
  tar_target(cfg_run, apply_years(cfg, years_info)),

  # --- 2 warehouse: raw -> staging -> mart (SQL) ----------------------------
  tar_files_input(sql_files, list.files(c("sql/raw", "sql/staging", "sql/mart"), "\\.sql$", full.names = TRUE)),
  # Private Track X input: tracked as a value so toggling the env var rebuilds the warehouse.
  tar_target(private_path, Sys.getenv("ZH_PRIVATE_ACCIDENTS"), cue = tar_cue(mode = "always")),
  tar_target(
    warehouse,
    build_warehouse(manifest, cfg_run, sql_files, "data/warehouse.duckdb",
                    private_path = private_path),
    format = "file"
  ),

  # --- 3 data quality: contracts + SQL checks + history -> gate -------------
  tar_files_input(dq_check_files, list.files("sql/dq", "\\.sql$", full.names = TRUE)),
  tar_files_input(dq_contract_files, list.files("dq/contracts", "\\.yml$", full.names = TRUE)),
  tar_target(
    dq_results,
    run_dq(warehouse, manifest, cfg_run, dq_check_files, dq_contract_files,
           history_file = "export/dq/snapshot_history.csv",
           report_dir = "export/dq", years_info = years_info,
           range_file = "export/dq/jahresbereich.csv")
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
  # Severity ladder (8 models): tune on training years only -> freeze -> evaluate on the test years.
  tar_files_input(model_cfg_file, "config/modell.yml"),
  tar_target(model_cfg, yaml::read_yaml(model_cfg_file)),
  tar_target(severity_data, {
    dq_passed
    load_severity_data(warehouse)
  }),
  tar_target(severity_plan, model_year_plan(cfg_run$years$to, cfg_run$years$from)),
  tar_target(sev_zeit, run_ladder(severity_data, severity_plan, "zeitlich", model_settings(model_cfg),
                                  interpret = TRUE)),
  tar_target(sev_zufall, run_ladder(severity_data, severity_plan, "zufaellig", model_settings(model_cfg),
                                    only = sev_zeit$best_tuned)),
  tar_target(sev_boot_zeit, run_bootstrap(sev_zeit, model_settings(model_cfg))),
  tar_target(sev_boot_zufall, run_bootstrap(sev_zufall, model_settings(model_cfg))),

  # --- 5 export: the only path to the public (all behind dq_passed) ---------
  tar_target(export_public_files, {
    dq_passed
    export_public(warehouse, export_cfg)
  }, format = "file"),
  tar_target(export_model_files, {
    dq_passed
    export_models(severity_model)
  }, format = "file"),
  tar_target(export_ladder_files, {
    dq_passed
    export_ladder(sev_zeit, sev_zufall, sev_boot_zeit, sev_boot_zufall, model_settings(model_cfg), severity_plan)
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
    build_dcat(export_cfg, cfg_run, export_public_files,
               site_url = "https://ffahrenb.github.io/zurich-road-accidents/")
  }, format = "file")
)
