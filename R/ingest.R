# Ingestion: fetch every source from its official endpoint into a dated snapshot.
# Each file is checksummed; the manifest makes silent upstream changes visible.

ckan_package <- function(cfg, ckan_id) {
  resp <- httr2::request(cfg$ckan_base) |>
    httr2::req_url_path_append("package_show") |>
    httr2::req_url_query(id = ckan_id) |>
    httr2::req_retry(max_tries = 3) |>
    httr2::req_perform()
  httr2::resp_body_json(resp)$result
}

ckan_resource_url <- function(pkg, name) {
  hit <- Filter(function(r) identical(r$name, name), pkg$resources)
  if (length(hit) != 1) stop("resource not found: ", name, " in ", pkg$name)
  hit[[1]]$url
}

wfs_url <- function(cfg, wfs) {
  paste0(
    cfg$wfs_base, "/", wfs$service,
    "?service=WFS&version=1.1.0&request=GetFeature",
    "&typename=", wfs$layer,
    "&outputFormat=application/vnd.geo%2Bjson"
  )
}

download_file <- function(url, dest) {
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  httr2::request(url) |>
    httr2::req_retry(max_tries = 3) |>
    httr2::req_timeout(300) |>
    httr2::req_perform(path = dest)
  dest
}

# Returns a data frame (one row per file) = manifest entries of this snapshot.
fetch_source <- function(cfg, key, snapshot_dir, years = NULL) {
  src <- cfg$sources[[key]]
  pkg <- ckan_package(cfg, src$ckan_id)
  targets_ <- if (!is.null(src[["resource"]])) {
    list(list(name = src[["resource"]], url = ckan_resource_url(pkg, src[["resource"]])))
  } else if (!is.null(src[["resource_pattern"]])) {
    lapply(years, function(y) {
      nm <- sub("{year}", y, src[["resource_pattern"]], fixed = TRUE)
      list(name = nm, url = ckan_resource_url(pkg, nm))
    })
  } else {
    list(list(name = paste0(src$wfs$layer, ".geojson"), url = wfs_url(cfg, src$wfs)))
  }
  rows <- lapply(targets_, function(t) {
    dest <- file.path(snapshot_dir, key, t$name)
    download_file(t$url, dest)
    data.frame(
      source = key, file = t$name, path = dest,
      bytes = file.size(dest),
      sha256 = digest_sha256(dest),
      source_modified = pkg$metadata_modified,
      retrieved_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      licence = src$licence,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

digest_sha256 <- function(path) {
  out <- system2("sha256sum", shQuote(path), stdout = TRUE)
  sub(" .*", "", out)
}

# Download all sources into data/raw/<date>/. Reuses an existing complete
# snapshot of the same day (idempotent reruns, no hammering of the portal).
# Order matters: single-file sources first, because the year range (years.to = auto) is resolved
# from the accident file, the population file and the per-year resources listed in CKAN; only then
# are the per-year files (meteo, luft) downloaded. The range is stored in years.csv and in the
# year_from / year_to columns of the manifest.
fetch_all <- function(cfg, snapshot_date, root = "data/raw") {
  dir <- file.path(root, snapshot_date)
  manifest_file <- file.path(dir, "manifest.csv")
  if (file.exists(manifest_file) && file.exists(file.path(dir, "years.csv"))) {
    return(utils::read.csv(manifest_file, stringsAsFactors = FALSE))
  }
  keys <- names(cfg$sources)
  per_year <- vapply(cfg$sources, function(s) !is.null(s[["resource_pattern"]]), logical(1))
  fixed <- do.call(rbind, lapply(keys[!per_year], function(key) fetch_source(cfg, key, dir)))
  res <- resolve_snapshot_years(cfg, fixed)
  years <- seq(res$year_from, res$year_to)
  dated <- do.call(rbind, lapply(keys[per_year], function(key) fetch_source(cfg, key, dir, years = years)))
  manifest <- rbind(fixed, dated)
  manifest <- manifest[order(match(manifest$source, keys)), ]
  manifest$year_from <- res$year_from
  manifest$year_to <- res$year_to
  rownames(manifest) <- NULL
  utils::write.csv(years_row(res, snapshot_date), file.path(dir, "years.csv"), row.names = FALSE)
  utils::write.csv(manifest, manifest_file, row.names = FALSE)
  manifest
}
