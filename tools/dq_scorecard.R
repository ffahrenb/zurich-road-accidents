# DQ scorecard: tile grid source x dimension from export/dq/dq_ergebnisse.csv -> docs/img/dq-scorecard.png
# Usage (repo root): Rscript tools/dq_scorecard.R
# Colour is never the only carrier: every tile also states the status and the check counts.
suppressPackageStartupMessages(library(ggplot2))

res <- utils::read.csv("export/dq/dq_ergebnisse.csv", stringsAsFactors = FALSE, encoding = "UTF-8")

# Display name for the non-public source; nothing beyond "not public" is stated on purpose.
res$quelle[res$quelle == "privat"] <- "nicht öffentlich"

status_levels <- c("PASS", "WARN", "STOP")
fills <- c(PASS = "#0ca30c", WARN = "#fab219", STOP = "#d03b3b")
texts <- c(PASS = "#0b0b0b", WARN = "#0b0b0b", STOP = "#ffffff")
surface <- "#fcfcfb"
ink <- "#0b0b0b"

# Worst status per tile; an unknown (NA) status counts as failing at the check's severity.
res$status[is.na(res$status)] <- res$schwere[is.na(res$status)]
res$rank <- match(res$status, status_levels)

tiles <- do.call(rbind, lapply(split(res, list(res$quelle, res$dimension), drop = TRUE), function(d) {
  data.frame(quelle = d$quelle[1], dimension = d$dimension[1], n = nrow(d),
             n_bad = sum(d$status != "PASS"), status = status_levels[max(d$rank)],
             stringsAsFactors = FALSE)
}))
tiles$label <- ifelse(tiles$n_bad == 0,
                      sprintf("%s\n%d %s", tiles$status, tiles$n, ifelse(tiles$n == 1, "Prüfung", "Prüfungen")),
                      sprintf("%s\n%d von %d auffällig", tiles$status, tiles$n_bad, tiles$n))
tiles$status <- factor(tiles$status, levels = status_levels)

quellen <- sort(unique(res$quelle))
dims <- unique(res$dimension)
tiles$quelle <- factor(tiles$quelle, levels = rev(quellen))
tiles$dimension <- factor(tiles$dimension, levels = dims)
grid <- expand.grid(quelle = factor(quellen, levels = rev(quellen)), dimension = factor(dims, levels = dims))

n_all <- nrow(res)
n_ok <- sum(res$status == "PASS")
snap <- max(res$snapshot)

p <- ggplot() +
  geom_tile(data = grid, aes(dimension, quelle), fill = "#efeeea", colour = surface, linewidth = 2) +
  geom_tile(data = tiles, aes(dimension, quelle, fill = status), colour = surface, linewidth = 2) +
  geom_text(data = tiles, aes(dimension, quelle, label = label, colour = status),
            size = 3.6, lineheight = 1.05, fontface = "bold") +
  scale_fill_manual(values = fills, drop = FALSE, name = NULL) +
  scale_colour_manual(values = texts, guide = "none") +
  scale_x_discrete(position = "top", labels = function(x) gsub(" ", "\n", x, fixed = TRUE)) +
  labs(title = "Datenqualität: Prüfergebnisse je Quelle und Dimension",
       subtitle = sprintf(paste0("%d von %d automatischen Prüfungen bestanden · Stand %s · ",
                                 "PASS = in Ordnung, WARN = Hinweis, STOP = Veröffentlichung gesperrt"),
                          n_ok, n_all, snap),
       x = NULL, y = NULL) +
  theme_minimal(base_family = "sans", base_size = 12) +
  theme(plot.background = element_rect(fill = surface, colour = NA),
        panel.background = element_rect(fill = surface, colour = NA),
        panel.grid = element_blank(),
        text = element_text(colour = ink),
        axis.text = element_text(colour = ink),
        axis.text.x = element_text(face = "bold"),
        plot.title = element_text(face = "bold", size = 16),
        plot.subtitle = element_text(size = 10, margin = margin(b = 8)),
        plot.title.position = "plot",
        legend.position = "none",   # the subtitle is the legend (STOP may have no tile)
        plot.margin = margin(14, 16, 10, 14))

dir.create("docs/img", recursive = TRUE, showWarnings = FALSE)
out <- "docs/img/dq-scorecard.png"
ggsave(out, p, width = 12, height = 6, dpi = 100, bg = surface,
       device = if (requireNamespace("ragg", quietly = TRUE)) ragg::agg_png else "png")
cat("wrote ", out, "\n", sep = "")
