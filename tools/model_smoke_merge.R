# Merges the two smoke phases (time + peak memory) into config/modell_smoke.json with a linear projection.
# Usage: Rscript tools/model_smoke_merge.R <tmpdir> <fraction>
args <- commandArgs(trailingOnly = TRUE)
tmp <- args[1]
frac <- as.numeric(args[2])
read_phase <- function(ph) {
  j <- jsonlite::read_json(file.path(tmp, paste0(ph, ".json")))
  tl <- readLines(file.path(tmp, paste0(ph, ".time")))
  kb <- as.numeric(sub(".*: ", "", grep("Maximum resident", tl, value = TRUE)))
  cg <- as.numeric(readLines(file.path(tmp, paste0(ph, ".cg"))))
  rt <- do.call(rbind, lapply(j$laufzeit, as.data.frame))
  by_model <- if (is.null(rt)) NULL else as.list(round(tapply(rt$sekunden, rt$modell, sum), 1))
  list(sekunden = round(j$sekunden, 1), spitze_prozess_mb = round(kb / 1024),
       spitze_container_mb = round(cg / 1024^2), threads = j$threads, n = j$n, sekunden_je_modell = by_model)
}
t <- read_phase("tuning")
b <- read_phase("bootstrap")
proj <- (t$sekunden + b$sekunden) / frac
out <- list(
  datum = format(Sys.time(), "%Y-%m-%d"), anteil = frac, tuning = t, bootstrap = b,
  hinweis = paste0("spitze_prozess_mb = groesster Einzelprozess (/usr/bin/time -v), je Phase getrennt; ",
                   "spitze_container_mb = cgroup memory.peak, kumulativ seit Containerstart (Phasen nacheinander im ",
                   "selben Container, enthaelt Page-Cache)"),
  hochrechnung = list(
    tuning_sekunden = round(t$sekunden / frac), bootstrap_sekunden = round(b$sekunden / frac),
    gesamt_sekunden = round(proj), gesamt_minuten = round(proj / 60, 1),
    spitze_container_mb_100pct = round(max(t$spitze_container_mb, b$spitze_container_mb) / frac),
    methode = "linear in 1/anteil (Trainingszeilen bzw. Bootstrap-Ziehungen)"
  )
)
jsonlite::write_json(out, "config/modell_smoke.json", auto_unbox = TRUE, pretty = TRUE)
cat(jsonlite::toJSON(out, auto_unbox = TRUE, pretty = TRUE), "\n")
