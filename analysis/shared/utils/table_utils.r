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
APA_FONT    <- "Times New Roman"
APA_BODY_PT <- 10
APA_HEAD_PT <- 10
APA_PAGE_W  <- 6.5   # text width in inches (letter paper, 1-inch margins)


#' Apply APA 7th formatting to a flextable
#'
#' Converts a data frame to a flextable with APA style: Times New Roman,
#' top and bottom borders only (no vertical rules, no internal horizontals
#' except under the header row), right-aligned numeric columns.
#'
#' @param df    A data frame or tibble
#' @param col_widths Optional named numeric vector of column widths in inches.
#'   Names must match column names in df. Unspecified columns are auto-fitted.
#' @return A flextable object
#'
apa_flextable <- function(df, col_widths = NULL) {
    ft <- flextable::flextable(df)

    # Font
    ft <- flextable::font(ft, fontname = APA_FONT, part = "all")
    ft <- flextable::fontsize(ft, size = APA_BODY_PT, part = "body")
    ft <- flextable::fontsize(ft, size = APA_HEAD_PT, part = "header")

    # Bold header
    ft <- flextable::bold(ft, part = "header")

    # Remove all borders, then add APA top/bottom/header-bottom
    ft <- flextable::border_remove(ft)
    top_border    <- officer::fp_border(width = 1.5)
    bottom_border <- officer::fp_border(width = 1.5)
    head_bottom   <- officer::fp_border(width = 0.75)

    ft <- flextable::hline_top(ft, border = top_border, part = "header")
    ft <- flextable::hline_bottom(ft, border = head_bottom, part = "header")
    ft <- flextable::hline_bottom(ft, border = bottom_border, part = "body")

    # Column alignment: right-align numeric, left-align character/factor
    num_cols  <- names(df)[vapply(df, is.numeric, logical(1))]
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
    note_props  <- officer::fp_text(italic = TRUE,  font.family = APA_FONT, font.size = APA_BODY_PT)
    body_props  <- officer::fp_text(italic = FALSE, font.family = APA_FONT, font.size = APA_BODY_PT)
    flextable::add_footer_lines(ft, values = "") |>
        flextable::compose(
            part  = "footer", i = 1, j = 1,
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
    doc <- officer::read_docx()
    doc <- officer::body_add_par(doc, paste0("Table ", table_num), style = "Normal")
    doc <- officer::body_add_par(doc, title, style = "Normal")
    doc <- flextable::body_add_flextable(doc, ft)
    # officer 0.7.x: prop_section() is broken in-pipeline; use body_end_section_portrait()
    # which seals the section with default letter-page portrait settings
    doc <- officer::body_end_section_portrait(doc)

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
    if (any(is.na(c(b, se, p)))) return("")
    stars <- dplyr::case_when(
        p < .001 ~ "***",
        p < .01  ~ "**",
        p < .05  ~ "*",
        TRUE     ~ ""
    )
    fmt <- paste0("%.", digits, "f")
    paste0(sprintf(fmt, b), stars, " (", sprintf(fmt, se), ")")
}


#' Format a p-value per APA 7th conventions
#'
#' Reports exact p to three decimal places, except values below .001
#' which are reported as "< .001".
#'
#' @param p Numeric p-value (scalar or vector)
#' @return Character string(s)
#'
fmt_p <- function(p) {
    dplyr::case_when(
        is.na(p)  ~ "",
        p < .001  ~ "< .001",
        TRUE      ~ paste0("= ", sub("^0", "", formatC(p, digits = 3, format = "f")))
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
