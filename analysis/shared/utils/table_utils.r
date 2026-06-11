#!/usr/bin/env Rscript

# ---------------------------------------------------------------------------
# table_utils.r - Shared APA 7th Word table utilities
#
# Provides flextable helpers for producing publication-ready .docx tables
# targeting JAP / Psychological Methods formatting standards.
#
# Requires: common_utils.r sourced first (for log_msg)
# ---------------------------------------------------------------------------

library(flextable)
library(officer)


# APA formatting constants
APA_FONT <- "Times New Roman"
APA_BODY_PT <- 12
APA_HEAD_PT <- 12
APA_PAGE_W <- 6.5 # text width in inches (letter paper, 1-inch margins)
APA_PAGE_W_LANDSCAPE <- 9.0 # text width in landscape (11-inch paper, 1-inch margins)

# intToUtf8() keeps source ASCII-clean; U+2014 = 8212, U+2013 = 8211
EMDASH <- intToUtf8(8212L)
ENDASH <- intToUtf8(8211L)

GREEK <- c(
    tau_00 = "τ₀₀",
    tau_11 = "τ₁₁",
    sigma2 = "σ²",
    R2m    = "R² (marg.)",
    R2c    = "R² (cond.)",
    chi2   = "χ²",
    beta   = "β",
    lambda = "λ",
    omega  = "ω"
)


#' Apply APA 7th formatting to a flextable
#'
#' Converts a data frame to a flextable with APA style: Times New Roman,
#' top and bottom borders only (no vertical rules, no internal horizontals
#' except under the header row), right-aligned numeric columns.
#'
#' @param df    A data frame or tibble
#' @param col_widths Optional named numeric vector of column widths in inches.
#'   Names must match column names in df. Unspecified columns are auto-fitted.
#' @param spanners Optional named list for spanner (grouped) column headers. Names
#'   are spanner labels; values are character vectors of column names under each
#'   spanner. E.g. list("M7a" = c("b_7a", "se_7a"), "M7b" = c("b_7b", "se_7b")).
#' @return A flextable object
#'
apa_flextable <- function(df, col_widths = NULL, spanners = NULL) {
    ft <- flextable::flextable(df)

    # Spanner header row must be added before borders so hline_top targets the new top row
    if (!is.null(spanners)) {
        col_names <- names(df)
        header_vals <- character(length(col_names))
        for (span_label in names(spanners)) {
            header_vals[col_names %in% spanners[[span_label]]] <- span_label
        }
        ft <- flextable::add_header_row(ft, values = header_vals, top = TRUE)
        ft <- flextable::merge_h(ft, part = "header")
    }

    # Font
    ft <- flextable::font(ft, fontname = APA_FONT, part = "all")
    ft <- flextable::fontsize(ft, size = APA_BODY_PT, part = "body")
    ft <- flextable::fontsize(ft, size = APA_HEAD_PT, part = "header")

    # Bold header
    ft <- flextable::bold(ft, part = "header")

    # Remove all borders, then add APA top/bottom/header-bottom
    ft <- flextable::border_remove(ft)
    top_border <- officer::fp_border(width = 1.5)
    bottom_border <- officer::fp_border(width = 1.5)
    head_bottom <- officer::fp_border(width = 0.75)

    ft <- flextable::hline_top(ft, border = top_border, part = "header")
    ft <- flextable::hline_bottom(ft, border = head_bottom, part = "header")
    ft <- flextable::hline_bottom(ft, border = bottom_border, part = "body")

    # Column alignment: right-align numeric, left-align character/factor
    num_cols <- names(df)[vapply(df, is.numeric, logical(1))]
    char_cols <- setdiff(names(df), num_cols)

    if (length(num_cols) > 0) {
        ft <- flextable::align(ft, j = num_cols, align = "right", part = "all")
    }
    if (length(char_cols) > 0) {
        ft <- flextable::align(ft, j = char_cols, align = "left", part = "all")
    }

    # Padding
    ft <- flextable::padding(ft, padding.top = 2, padding.bottom = 2, part = "all")

    # Column widths
    if (!is.null(col_widths)) {
        for (col in names(col_widths)) {
            ft <- flextable::width(ft, j = col, width = col_widths[[col]])
        }
    } else {
        ft <- flextable::autofit(ft, add_w = 0.1)
        ft <- flextable::fit_to_width(ft, max_width = APA_PAGE_W)
    }

    ft
}


#' Add an APA-format general note below a flextable
#'
#' Appends a footer row formatted as: italic "Note." followed by regular text.
#'
#' @param ft        A flextable object
#' @param note_text Character string for the note body (after "Note.")
#' @return The modified flextable
#'
add_apa_note <- function(ft, note_text) {
    note_props <- officer::fp_text(italic = TRUE, font.family = APA_FONT, font.size = APA_BODY_PT)
    body_props <- officer::fp_text(italic = FALSE, font.family = APA_FONT, font.size = APA_BODY_PT)
    flextable::add_footer_lines(ft, values = "") |>
        flextable::compose(
            part = "footer", i = 1, j = 1,
            value = flextable::as_paragraph(
                flextable::as_chunk("Note.", props = note_props),
                flextable::as_chunk(paste0(" ", note_text), props = body_props)
            )
        )
}


#' Save a flextable as a standalone Word document
#'
#' Wraps the table in an officer document with APA-style table caption
#' ("Table N" bold, title italic on next line), 1-inch margins, and saves
#' as a .docx file. Each table goes in its own document for easy insertion
#' into the manuscript.
#'
#' @param ft          A flextable object
#' @param filepath    Full output path (including .docx extension)
#' @param table_num   Integer table number (used in "Table N" caption)
#' @param title       Character string for the table title (italicized)
#' @return NULL (invisible); called for side effect
#'
save_docx_table <- function(ft, filepath, table_num, title) {
    num_props <- officer::fp_text(bold = TRUE, font.family = APA_FONT, font.size = APA_BODY_PT)
    title_props <- officer::fp_text(italic = TRUE, font.family = APA_FONT, font.size = APA_BODY_PT)
    doc <- officer::read_docx()
    doc <- officer::body_add_fpar(
        doc,
        officer::fpar(officer::ftext(paste0("Table ", table_num), prop = num_props))
    )
    doc <- officer::body_add_fpar(
        doc,
        officer::fpar(officer::ftext(title, prop = title_props))
    )
    doc <- flextable::body_add_flextable(doc, ft)
    doc <- officer::body_end_section_portrait(doc)
    print(doc, target = filepath)
    log_msg("Saved: ", filepath)
    invisible(NULL)
}


#' Save multiple flextable panels as a single Word document
#'
#' Writes a caption (bold table number, italic title), then each panel with an
#' optional bold panel label, separated by blank lines. Used for tables with
#' Panel A / Panel B structure (e.g. CFA fit + loadings, Table 2a/2b).
#'
#' @param panels   List of lists, each with elements: $label (character, may be
#'   empty) and $ft (a flextable object).
#' @param filepath Full output path (including .docx extension)
#' @param table_num Integer or character table number/identifier
#' @param title    Character string for the table title (italicized)
#' @return NULL (invisible); called for side effect
#'
save_docx_tables <- function(panels, filepath, table_num, title) {
    num_props <- officer::fp_text(bold = TRUE, font.family = APA_FONT, font.size = APA_BODY_PT)
    title_props <- officer::fp_text(italic = TRUE, font.family = APA_FONT, font.size = APA_BODY_PT)
    panel_props <- officer::fp_text(bold = TRUE, font.family = APA_FONT, font.size = APA_BODY_PT)
    doc <- officer::read_docx()
    doc <- officer::body_add_fpar(
        doc,
        officer::fpar(officer::ftext(paste0("Table ", table_num), prop = num_props))
    )
    doc <- officer::body_add_fpar(
        doc,
        officer::fpar(officer::ftext(title, prop = title_props))
    )
    for (i in seq_along(panels)) {
        panel <- panels[[i]]
        if (!is.null(panel$label) && nzchar(panel$label)) {
            doc <- officer::body_add_fpar(
                doc,
                officer::fpar(officer::ftext(panel$label, prop = panel_props))
            )
        }
        doc <- flextable::body_add_flextable(doc, panel$ft)
        if (i < length(panels)) {
            doc <- officer::body_add_par(doc, "", style = "Normal")
        }
    }
    doc <- officer::body_end_section_portrait(doc)
    print(doc, target = filepath)
    log_msg("Saved: ", filepath)
    invisible(NULL)
}


#' Save a flextable as a landscape-oriented Word document
#'
#' Same as save_docx_table() but seals the section as landscape for wide tables.
#' Caller is responsible for setting col_widths to fit within APA_PAGE_W_LANDSCAPE.
#'
#' @param ft          A flextable object
#' @param filepath    Full output path (including .docx extension)
#' @param table_num   Integer table number (used in "Table N" caption)
#' @param title       Character string for the table title (italicized)
#' @return NULL (invisible); called for side effect
#'
save_docx_table_landscape <- function(ft, filepath, table_num, title) {
    num_props <- officer::fp_text(bold = TRUE, font.family = APA_FONT, font.size = APA_BODY_PT)
    title_props <- officer::fp_text(italic = TRUE, font.family = APA_FONT, font.size = APA_BODY_PT)
    landscape_ps <- officer::prop_section(
        page_size = officer::page_size(width = 11, height = 8.5, orient = "landscape"),
        page_margins = officer::page_mar(bottom = 1, top = 1, right = 1, left = 1)
    )
    doc <- officer::read_docx()
    doc <- officer::body_set_default_section(doc, landscape_ps)
    doc <- officer::body_add_fpar(
        doc,
        officer::fpar(officer::ftext(paste0("Table ", table_num), prop = num_props))
    )
    doc <- officer::body_add_fpar(
        doc,
        officer::fpar(officer::ftext(title, prop = title_props))
    )
    doc <- flextable::body_add_flextable(doc, ft)
    print(doc, target = filepath)
    log_msg("Saved: ", filepath)
    invisible(NULL)
}


#' Format a regression coefficient cell as "B (SE)" with significance stars
#'
#' @param b      Numeric coefficient estimate
#' @param se     Numeric standard error
#' @param p      Numeric p-value
#' @param digits Integer decimal places (default 2)
#' @return Character string, e.g. "0.34** (0.08)"
#'
fmt_est <- function(b, se, p, digits = 2) {
    if (any(is.na(c(b, se, p)))) {
        return("")
    }
    stars <- dplyr::case_when(
        p < .001 ~ "***",
        p < .01 ~ "**",
        p < .05 ~ "*",
        TRUE ~ ""
    )
    fmt <- paste0("%.", digits, "f")
    paste0(sprintf(fmt, b), stars, " (", sprintf(fmt, se), ")")
}


#' Format a p-value per APA 7th conventions (column style)
#'
#' Reports exact p to three decimal places without a leading zero (".013");
#' values below .001 are reported as "< .001". For sentence contexts
#' ("p = .013"), the caller prepends "= " when the value is exact.
#'
#' @param p Numeric p-value (scalar or vector)
#' @return Character string(s)
#'
fmt_p <- function(p) {
    dplyr::case_when(
        is.na(p) ~ "",
        p < .001 ~ "< .001",
        TRUE ~ sub("^0", "", formatC(p, digits = 3, format = "f"))
    )
}


#' Format a correlation or bounded statistic per APA conventions
#'
#' Drops the leading zero for statistics bounded between -1 and 1
#' (e.g., "0.45" becomes ".45", "-0.32" becomes "-.32").
#'
#' @param r     Numeric value(s)
#' @param digits Integer decimal places (default 2)
#' @return Character string(s)
#'
fmt_r <- function(r, digits = 2) {
    fmt <- paste0("%.", digits, "f")
    formatted <- sprintf(fmt, r)
    # Drop leading zero: "0." -> ".", "-0." -> "-."
    formatted <- sub("^0\\.", ".", formatted)
    formatted <- sub("^-0\\.", "-.", formatted)
    dplyr::if_else(is.na(r), "", formatted)
}


#' Format a confidence interval as "[lo, hi]"
#'
#' For regression coefficient CIs (unbounded); leading zeros are retained.
#'
#' @param lo    Numeric lower bound
#' @param hi    Numeric upper bound
#' @param digits Integer decimal places (default 2)
#' @return Character string, e.g. "[-0.12, 0.34]"
#'
fmt_ci <- function(lo, hi, digits = 2) {
    if (any(is.na(c(lo, hi)))) {
        return("")
    }
    fmt <- paste0("%.", digits, "f")
    paste0("[", sprintf(fmt, lo), ", ", sprintf(fmt, hi), "]")
}
