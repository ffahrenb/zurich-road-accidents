# Pre-render: bring the committed export/ into the site, derive JSON-LD and llms.txt.
# The site reads ONLY export/ (copied to site/export, which is git-ignored).
suppressPackageStartupMessages(library(jsonlite))
site <- Sys.getenv("QUARTO_PROJECT_DIR", getwd())
src <- normalizePath(file.path(site, "..", "export"), mustWork = TRUE)
dst <- file.path(site, "export")
unlink(dst, recursive = TRUE)
file.copy(src, site, recursive = TRUE)

# The pointblank reports pull a web font and a CSS file from third-party CDNs.
# Strip both so the published copy makes no third-party request.
for (f in list.files(file.path(dst, "dq"), pattern = "^vertrag_.*\\.html$", full.names = TRUE)) {
  x <- readLines(f, warn = FALSE, encoding = "UTF-8")
  x <- gsub('@import url\\("https://(fonts\\.googleapis\\.com|unpkg\\.com)[^"]*"\\);?', "", x)
  writeLines(x, f, useBytes = TRUE)
}

# ---- facts for schema.org JSON-LD and llms.txt, all derived from export/ ----
kat <- fromJSON(file.path(dst, "meta", "katalog.jsonld"), simplifyVector = FALSE)
ds <- kat[["dcat:dataset"]][[1]]
lang_val <- function(x, l) Filter(function(v) identical(v[["@language"]], l), x)[[1]][["@value"]]
dq <- read.csv(file.path(dst, "dq", "dq_ergebnisse.csv"), encoding = "UTF-8")
u <- read.csv(file.path(dst, "data", "jahr.csv"), encoding = "UTF-8")
n_acc <- sum(u$unfaelle)
yrs <- range(u$jahr)
base <- "https://ffahrenb.github.io/zurich-road-accidents/"
dists <- lapply(ds[["dcat:distribution"]], function(d) {
  list(
    "@type" = "DataDownload",
    contentUrl = d[["dcat:downloadURL"]][["@id"]],
    encodingFormat = basename(d[["dcat:downloadURL"]][["@id"]])
  )
})
dists <- c(dists, list(list("@type" = "DataDownload",
  contentUrl = paste0(base, "export/meta/katalog.jsonld"), encodingFormat = "application/ld+json")))
ld <- list(
  "@context" = "https://schema.org",
  "@type" = "Dataset",
  name = lang_val(ds[["dct:title"]], "de"),
  alternateName = lang_val(ds[["dct:title"]], "en"),
  description = sprintf(
    paste0("Strassenverkehrsunfälle in der Stadt Zürich %d–%d (%s Unfälle), angereichert mit Quartier, Tempo ",
           "und Schulnähe; geprüft durch %d automatische Datenqualitäts-Checks."),
    yrs[1], yrs[2], format(n_acc, big.mark = "’"), nrow(dq)),
  url = base,
  identifier = ds[["dct:identifier"]],
  inLanguage = c("de", "en"),
  keywords = c("Verkehrsunfall", "Verkehrssicherheit", "Zürich", "Open Data", "road safety", "Datenqualität"),
  temporalCoverage = sprintf("%d-01-01/%d-12-31", yrs[1], yrs[2]),
  spatialCoverage = list("@type" = "Place", name = "Stadt Zürich, Schweiz"),
  license = "https://creativecommons.org/licenses/by/4.0/",
  isAccessibleForFree = TRUE,
  creator = list("@type" = "Person", name = ds[["dct:publisher"]][["foaf:name"]]),
  isBasedOn = vapply(ds[["prov:wasDerivedFrom"]], function(x) x[["@id"]], ""),
  dateModified = substr(ds[["dct:modified"]], 1, 10),
  citation = "Quelle: Stadt Zürich, Open Data / Bundesamt für Strassen ASTRA, CC BY 4.0",
  distribution = dists
)
# Quarto variables ({{< var yr_span >}}) for the titles in front matter and _quarto.yml.
writeLines(sprintf("yr_span: \"%d–%d\"", yrs[1], yrs[2]), file.path(site, "_variables.yml"), useBytes = TRUE)
writeLines(c('<script type="application/ld+json">', toJSON(ld, auto_unbox = TRUE, pretty = TRUE), "</script>"),
           file.path(site, "_dataset-jsonld.html"), useBytes = TRUE)

# ---- llms.txt ----
files <- list.files(dst, recursive = TRUE)
llms <- c(
  sprintf("# Unfälle Zürich – Strassenverkehrsunfälle %d–%d", yrs[1], yrs[2]),
  "",
  sprintf(paste0("> Offene Auswertung von %s Strassenverkehrsunfällen der Stadt Zürich (%d–%d). ",
                 "R+SQL-Pipeline (DuckDB), %d automatische Datenqualitäts-Prüfungen mit STOP-Gate, Modelle, ",
                 "offene Exporte. Daten: Stadt Zürich Open Data / ASTRA, CC BY 4.0. Code: MIT."),
          format(n_acc, big.mark = "'"), yrs[1], yrs[2], nrow(dq)),
  "",
  paste0(
    "Hinweise: 2015 steigt die Zahl der erfassten Unfälle um 38 %, wegen geänderter Erfassung ",
    "(DQ-U07, WARN). Das Schweremodell zeigt Zusammenhänge und ist kein Prognosewerkzeug. ",
    "Wetter-Effekte sind Verhältnisse (IRR) pro Stunde."
  ),
  "",
  "## Seiten",
  "",
  paste0("- [Übersicht](", base, "): Kennzahlen und Kernaussagen"),
  paste0("- [Datenqualität](", base,
         "datenqualitaet.html): Prüfübersicht, alle Prüfungen, STOP und WARN, Strukturbruch 2015"),
  paste0("- [Karte](", base, "karte.html): interaktive Karte, Quartier-Raten"),
  paste0("- [Wann](", base, "wann.html): Stunde × Wochentag, Jahrestrends"),
  paste0("- [Wo](", base, "wo.html): Quartiere, Tempoklassen, Schulnähe"),
  paste0("- [Wetter](", base, "wetter.html): Regen und Temperatur (negative Binomial, IRR)"),
  paste0("- [Schwere](", base, "schwere.html): Modell zur Unfallschwere, Grenzen"),
  paste0("- [Daten & Metadaten](", base, "daten.html): Downloads, DCAT-AP CH, Datenwörterbuch, Manifest"),
  paste0("- [Pipeline & Methode](", base, "pipeline.html): Lineage, Reproduzierbarkeit, Tests, ADRs"),
  paste0("- [Datenschutz](", base, "datenschutz.html): Privacy by Design"),
  paste0("- [English summary](", base, "en/index.html)"),
  "",
  "## Datendateien (maschinenlesbar)",
  "",
  paste0("- ", base, "export/", files[!grepl("\\.html$", files)]),
  "",
  "## Berichte (Datenverträge, HTML)",
  "",
  paste0("- ", base, "export/", files[grepl("\\.html$", files)]),
  "",
  "## Quelle und Lizenz",
  "",
  paste0("- Quelle: Stadt Zürich, Open Data / Bundesamt für Strassen ASTRA, CC BY 4.0 (Unfälle); ",
         "weitere Quellen CC0. Bitte bei Weiterverwendung nennen."),
  "- Repository: https://github.com/ffahrenb/zurich-road-accidents"
)
writeLines(llms, file.path(site, "llms.txt"), useBytes = TRUE)
invisible(NULL)
