#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# mlm_diagnostics.R — MLM residual and random-effect diagnostic plots
#
# Provides:
#   check_assumptions()  — 4-panel diagnostic SVG for a fitted lmer model
#
# Dependencies: ggplot2, patchwork, common_utils.r (log_msg),
#               plot_utils.r (save_svg) must be sourced first.
# ---------------------------------------------------------------------------

library(ggplot2)
library(patchwork)


#' Generate and save a 4-panel residual diagnostic SVG for a fitted lmer model
#'
#' Panels:
#'   1. L1 residual Q-Q plot
#'   2. Residuals vs. fitted values (with loess smoother)
#'   3. Random intercept Q-Q plot
#'   4. Scale-location plot (sqrt|residual| vs. fitted)
#'
#' @param fit        Fitted lmerModLmerTest; if NULL the function returns invisibly.
#' @param model_name Character label used in the plot title and output filename.
#' @param figs_dir   Character; directory to write the SVG into.
#' @return NULL (called for side effect).
#'
check_assumptions <- function(fit, model_name, figs_dir) {
    if (is.null(fit)) return(invisible(NULL))

    resids      <- residuals(fit)
    fitted_vals <- fitted(fit)
    re          <- ranef(fit)[[1]]

    # Panel 1: L1 residual Q-Q
    p1 <- ggplot2::ggplot(data.frame(r = resids), ggplot2::aes(sample = r)) +
        ggplot2::stat_qq(alpha = 0.3, size = 0.8) +
        ggplot2::stat_qq_line(color = "red") +
        ggplot2::labs(title = "L1 Residual Q-Q", x = "Theoretical", y = "Sample")

    # Panel 2: Residuals vs. fitted
    p2 <- ggplot2::ggplot(
        data.frame(fitted = fitted_vals, resid = resids),
        ggplot2::aes(x = fitted, y = resid)
    ) +
        ggplot2::geom_point(alpha = 0.2, size = 0.8) +
        ggplot2::geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
        ggplot2::geom_smooth(method = "loess", se = FALSE, color = "blue", linewidth = 0.6) +
        ggplot2::labs(title = "Residuals vs. Fitted", x = "Fitted", y = "Residual")

    # Panel 3: Random intercept Q-Q (only when model has a random intercept)
    has_ri <- !is.null(re) && "(Intercept)" %in% colnames(re)
    if (has_ri) {
        p3 <- ggplot2::ggplot(
            data.frame(ri = re[["(Intercept)"]]),
            ggplot2::aes(sample = ri)
        ) +
            ggplot2::stat_qq(alpha = 0.5, size = 0.8) +
            ggplot2::stat_qq_line(color = "red") +
            ggplot2::labs(title = "Random Intercept Q-Q", x = "Theoretical", y = "Sample")
    }

    # Panel 4: Scale-location
    p4 <- ggplot2::ggplot(
        data.frame(fitted = fitted_vals, sqrt_abs_resid = sqrt(abs(resids))),
        ggplot2::aes(x = fitted, y = sqrt_abs_resid)
    ) +
        ggplot2::geom_point(alpha = 0.2, size = 0.8) +
        ggplot2::geom_smooth(method = "loess", se = FALSE, color = "blue", linewidth = 0.6) +
        ggplot2::labs(
            title = "Scale-Location",
            x = "Fitted", y = expression(sqrt("|Residual|"))
        )

    panels   <- if (has_ri) (p1 | p2) / (p3 | p4) else (p1 | p2) / p4
    combined <- panels +
        patchwork::plot_annotation(
            title = paste("Model Diagnostics:", model_name),
            theme = ggplot2::theme(
                plot.title = ggplot2::element_text(face = "bold", size = 14)
            )
        )

    filename <- paste0(
        "mlm_diag_",
        gsub("[^a-z0-9]+", "_", tolower(model_name)), ".svg"
    )
    save_svg(combined, file.path(figs_dir, filename), width = 12, height = 9)
    invisible(NULL)
}
