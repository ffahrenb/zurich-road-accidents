# Shared helpers for all pages. Reads ONLY site/export (a copy of the committed export/).
suppressPackageStartupMessages({
  library(dplyr); library(tidyr); library(ggplot2); library(ggiraph)
  library(htmltools); library(scales); library(readr)
})

ROOT <- Sys.getenv("QUARTO_PROJECT_DIR", unset = normalizePath(".."))
EX <- file.path(ROOT, "export")
rd <- function(p) suppressMessages(read_csv(file.path(EX, p), show_col_types = FALSE, progress = FALSE,
                                            locale = locale(encoding = "UTF-8")))
SITE_URL <- "https://ffahrenb.github.io/zurich-road-accidents/"
REPO_URL <- "https://github.com/ffahrenb/zurich-road-accidents"

# ---------- number formatting (Swiss: apostrophe thousands, decimal point) ----------
fi <- function(x) format(round(x), big.mark = "’", scientific = FALSE, trim = TRUE)
fdec <- function(x, d = 1) format(round(x, d), nsmall = d, big.mark = "’", scientific = FALSE, trim = TRUE)
fp <- function(x, d = 0) paste0(format(round(x, d), nsmall = d, trim = TRUE), " %")

# ---------- palettes (dataviz system) ----------
CAT_L <- c("#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6", "#e34948")
CAT_D <- c("#3987e5", "#d95926", "#199e70", "#c98500", "#d55181", "#008300", "#9085e9", "#e66767")
VARIANTS <- list(
  light = list(name = "light", ink = "#0b0b0b", muted = "#55544f", grid = "#e1e0d9", bg = "#fcfcfb",
               cat = CAT_L, seq = colorRampPalette(c("#cde2fb", "#2a78d6", "#0d366b"))),
  dark = list(name = "dark", ink = "#f0efec", muted = "#a9a8a2", grid = "#2c2c2a", bg = "#1a1a19",
              cat = CAT_D, seq = colorRampPalette(c("#12294a", "#3987e5", "#cde2fb")))
)

theme_zh <- function(v, base = 11.5) {
  theme_minimal(base_size = base) +
    theme(
      text = element_text(colour = v$ink),
      plot.background = element_rect(fill = "transparent", colour = NA),
      panel.background = element_rect(fill = "transparent", colour = NA),
      panel.grid.major = element_line(colour = v$grid, linewidth = 0.3),
      panel.grid.minor = element_blank(),
      axis.text = element_text(colour = v$muted),
      axis.title = element_text(colour = v$muted, size = rel(0.92)),
      axis.ticks = element_blank(),
      legend.position = "bottom",
      legend.title = element_blank(),
      legend.text = element_text(colour = v$ink),
      legend.key.size = unit(0.9, "lines"),
      legend.margin = margin(0, 0, 0, 0),
      strip.text = element_text(colour = v$ink, face = "bold", hjust = 0),
      plot.title = element_blank(),
      plot.margin = margin(4, 8, 4, 4)
    )
}

# ---------- interactive chart wrapper ----------
HOVER_CSS <- "stroke:var(--ink);stroke-width:1.4px;"
TIP_CSS <- paste0("background:var(--surface);color:var(--ink);border:1px solid var(--grid);padding:.35rem .6rem;",
                  "border-radius:6px;font-size:.88rem;line-height:1.35;box-shadow:0 2px 8px rgba(0,0,0,.2);",
                  "font-family:system-ui,-apple-system,'Segoe UI',Roboto,Arial,sans-serif;max-width:260px;")

gi <- function(gg, w, h, hover = HOVER_CSS, inv = "opacity:.45;") {
  girafe(ggobj = gg, width_svg = w, height_svg = h, bg = "transparent",
         options = list(
           opts_sizing(rescale = TRUE, width = 1),
           opts_tooltip(css = TIP_CSS, opacity = 1, use_cursor_pos = TRUE, offx = 10, offy = 12),
           opts_hover(css = hover),
           opts_hover_inv(css = inv),
           opts_toolbar(saveaspng = FALSE, hidden = c("lasso_select", "lasso_deselect", "zoom_onoff", "zoom_rect", "zoom_reset"))
         ))
}

# plot_fn(v) builds a ggplot for variant v. Both variants are rendered; CSS shows the one matching the theme.
chart <- function(plot_fn, headline, alt, caption = NULL, tbl = NULL, w = 5.6, h = 4,
                  hover = HOVER_CSS, inv = "opacity:.45;", tbl_label = "Tabelle zum Diagramm anzeigen") {
  tags$figure(
    class = "chart",
    tags$p(class = "takeaway", headline),
    tags$div(role = "img", `aria-label` = alt,
             tags$div(class = "only-light", gi(plot_fn(VARIANTS$light), w, h, hover, inv)),
             tags$div(class = "only-dark", gi(plot_fn(VARIANTS$dark), w, h, hover, inv))),
    if (!is.null(caption)) tags$figcaption(caption),
    if (!is.null(tbl)) tags$details(class = "chart-table", tags$summary(tbl_label), tbl)
  )
}

# ---------- plain HTML tables ----------
html_table <- function(df, digits = 1, caption = NULL, tall = FALSE, html_cols = character(), label = NULL, cls = NULL) {
  is_num <- vapply(df, is.numeric, logical(1))
  cell <- function(x, nm, num) {
    if (nm %in% html_cols) return(lapply(x, HTML))
    if (!num) return(as.character(x))
    ifelse(is.na(x), "–",
           ifelse(abs(x - round(x)) < 1e-9 & abs(x) >= 1, fi(x),
                  ifelse(abs(x) < 0.01 & x != 0, formatC(x, format = "e", digits = 1), fdec(x, digits))))
  }
  cols <- Map(cell, df, names(df), is_num)
  head <- tags$tr(lapply(seq_along(df), function(i) tags$th(scope = "col", class = if (is_num[i]) "num", names(df)[i])))
  body <- lapply(seq_len(nrow(df)), function(r) {
    tags$tr(lapply(seq_along(df), function(i) {
      val <- cols[[i]][[r]]
      tags$td(class = if (is_num[i]) "num", val)
    }))
  })
  tags$div(class = paste("tbl-wrap", if (tall) "tall"), tabindex = "0", role = "region",
           `aria-label` = label %||% caption %||% "Tabelle",
           tags$table(class = paste("tbl", cls), if (!is.null(caption)) tags$caption(caption), tags$thead(head), tags$tbody(body)))
}
`%||%` <- function(a, b) if (is.null(a)) b else a

# ---------- small components ----------
tiles <- function(...) {
  items <- list(...)
  tags$div(class = "tiles", lapply(items, function(t)
    tags$div(class = "tile", tags$div(class = "v", t$v), tags$div(class = "l", t$l),
             if (!is.null(t$n)) tags$div(class = "n", t$n))))
}
tile <- function(v, l, n = NULL) list(v = v, l = l, n = n)

note <- function(title, ..., kind = "") tags$div(class = paste("note", kind), tags$strong(class = "t", title), ...)

ICON <- list(
  good = '<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="7.2" fill="currentColor"/><path d="M4.6 8.4l2.3 2.3 4.5-5" stroke="#fff" stroke-width="1.9" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  warning = '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M8 1.2l7.4 13H.6z" fill="currentColor" stroke="currentColor" stroke-width="1" stroke-linejoin="round"/><path d="M8 6.2v3.9M8 12.2v.3" stroke="#1a1a19" stroke-width="1.8" stroke-linecap="round"/></svg>',
  critical = '<svg viewBox="0 0 16 16" aria-hidden="true"><rect x="1.2" y="1.2" width="13.6" height="13.6" rx="3" fill="currentColor"/><path d="M5.2 5.2l5.6 5.6M10.8 5.2l-5.6 5.6" stroke="#fff" stroke-width="1.9" stroke-linecap="round"/></svg>'
)
STATUS <- list(
  PASS = list(cls = "good", label = "Bestanden", label_en = "Pass"),
  WARN = list(cls = "warning", label = "Warnung", label_en = "Warning"),
  FAIL = list(cls = "critical", label = "Gestoppt", label_en = "Failed")
)
status_chip <- function(status, label = NULL, en = FALSE) {
  s <- STATUS[[status]] %||% STATUS$FAIL
  tags$span(class = paste("st", s$cls), HTML(ICON[[s$cls]]),
            label %||% if (en) s$label_en else s$label)
}
chip_html <- function(...) as.character(status_chip(...))
