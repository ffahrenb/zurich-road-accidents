# Metadata: machine-readable codebook + DCAT-AP CH catalogue (JSON-LD).
# Structure follows DCAT-AP CH (opendata.swiss / I14Y): Catalog > Dataset > Distribution.

build_dictionary <- function(export_cfg, codebook_file, out = "export/meta/datenwoerterbuch.csv") {
  cb <- yaml::read_yaml(codebook_file)
  rows <- do.call(rbind, lapply(names(export_cfg$public), function(key) {
    cols <- export_cfg$public[[key]]$columns
    data.frame(datensatz = key, spalte = cols,
               beschreibung_de = vapply(cols, function(c) or_else(cb[[c]]$de, NA_character_), ""),
               description_en = vapply(cols, function(c) or_else(cb[[c]]$en, NA_character_), ""),
               stringsAsFactors = FALSE)
  }))
  missing <- rows$spalte[is.na(rows$beschreibung_de)]
  if (length(missing)) stop("codebook missing: ", paste(unique(missing), collapse = ", "))
  write_csv(rows, out)
}

or_else <- function(a, b) if (is.null(a)) b else a

build_dcat <- function(export_cfg, cfg, files, site_url, out = "export/meta/katalog.jsonld") {
  now <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  eu_auth <- "http://publications.europa.eu/resource/authority/"
  media <- c(csv = "text/csv", parquet = "application/vnd.apache.parquet", geojson = "application/geo+json")
  src_ids <- vapply(cfg$sources, function(s) s$ckan_id, "")
  datasets <- lapply(names(export_cfg$public), function(key) {
    e <- export_cfg$public[[key]]
    dists <- lapply(e$formats, function(fmt) {
      f <- file.path("export/data", paste0(key, ".", fmt))
      list(
        "@type" = "dcat:Distribution",
        "dct:identifier" = paste0(key, ".", fmt),
        "dct:title" = list(list("@value" = paste(e$title_de, toupper(fmt)), "@language" = "de")),
        "dcat:accessURL" = list("@id" = paste0(site_url, "daten.html")),
        "dcat:downloadURL" = list("@id" = paste0(site_url, "export/data/", key, ".", fmt)),
        "dct:format" = list("@id" = paste0(eu_auth, "file-type/", toupper(fmt))),
        "dcat:mediaType" = list("@id" = paste0("https://www.iana.org/assignments/media-types/", media[[fmt]])),
        "dcat:byteSize" = if (file.exists(f)) file.size(f) else NULL,
        "dct:license" = list("@id" = "http://dcat-ap.ch/vocabulary/licenses/terms_by"),
        "dct:issued" = now, "dct:modified" = now
      )
    })
    list(
      "@type" = "dcat:Dataset",
      "dct:identifier" = paste0("zurich-road-accidents-", key, "@ffahrenb"),
      "dct:title" = list(list("@value" = e$title_de, "@language" = "de"),
                         list("@value" = e$title_en, "@language" = "en")),
      "dct:description" = list(
        list("@value" = paste0(e$title_de, ". Abgeleitet aus offenen Daten der Stadt Zürich und des ASTRA; ",
                               "automatisch erzeugt und qualitätsgeprüft (", length(e$columns),
                               " Spalten, siehe Datenwörterbuch)."), "@language" = "de"),
        list("@value" = paste0(e$title_en, ". Derived from open data of the City of Zurich and FEDRO; ",
                               "generated automatically and quality-checked."), "@language" = "en")),
      "dct:publisher" = list("@type" = "foaf:Agent", "foaf:name" = "Florian Fahrenbach"),
      "dcat:contactPoint" = list("@type" = "vcard:Organization", "vcard:fn" = "Florian Fahrenbach",
                                 "vcard:hasURL" = list(
                                   "@id" = "https://github.com/ffahrenb/zurich-road-accidents/issues")),
      "dcat:theme" = list(list("@id" = paste0(eu_auth, "data-theme/TRAN"))),
      "dcat:keyword" = list(list("@value" = "Verkehrsunfall", "@language" = "de"),
                            list("@value" = "Verkehrssicherheit", "@language" = "de"),
                            list("@value" = "road safety", "@language" = "en")),
      "dct:accessRights" = list("@id" = paste0(eu_auth, "access-right/PUBLIC")),
      "dct:spatial" = list("@id" = "https://ld.geo.admin.ch/boundaries/municipality/261"),
      "dct:temporal" = list("@type" = "dct:PeriodOfTime",
                            "dcat:startDate" = paste0(cfg$years$from, "-01-01"),
                            "dcat:endDate" = paste0(cfg$years$to, "-12-31")),
      "dct:accrualPeriodicity" = list("@id" = paste0(eu_auth, "frequency/ANNUAL")),
      "dct:issued" = now, "dct:modified" = now,
      "prov:wasDerivedFrom" = lapply(unname(src_ids), function(id) {
        list("@id" = paste0("https://data.stadt-zuerich.ch/dataset/", id))
      }),
      "dcat:landingPage" = list("@id" = site_url),
      "foaf:page" = list("@id" = paste0(site_url, "export/meta/datenwoerterbuch.csv")),
      "dcat:distribution" = dists
    )
  })
  doc <- list(
    "@context" = list(dcat = "http://www.w3.org/ns/dcat#", dct = "http://purl.org/dc/terms/",
                      foaf = "http://xmlns.com/foaf/0.1/", vcard = "http://www.w3.org/2006/vcard/ns#",
                      prov = "http://www.w3.org/ns/prov#", schema = "http://schema.org/"),
    "@type" = "dcat:Catalog",
    "dct:title" = list(list("@value" = "Strassenverkehrsunfälle Zürich – Datenkatalog", "@language" = "de"),
                       list("@value" = "Zurich road accidents – data catalogue", "@language" = "en")),
    "dct:publisher" = list("@type" = "foaf:Agent", "foaf:name" = "Florian Fahrenbach"),
    "dcat:dataset" = datasets
  )
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(doc, out, auto_unbox = TRUE, pretty = TRUE, null = "null")
  out
}
