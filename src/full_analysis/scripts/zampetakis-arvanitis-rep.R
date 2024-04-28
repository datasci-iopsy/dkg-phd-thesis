library(lme4)
library(readr)
library(tibble)
library(dplyr) # masks stats::filter, lag; base::intersect, setdiff, setequal, union
library(tidyr) # masks Matrix::expand, pack, unpack
library(performance)
library(lavaan)
library(rmcorr)

readr::read_delim(
    file = "src/data/processed/modelAll.dat",
    delim = ",",
    col_names = FALSE,
    # na = c(-9999) # no missing data
) -> raw
summary(raw)

c(
    "id",
    "down_tem",
    "up_tem",
    "down_soc",
    "up_soc",
    "ocb_ch",
    "aut_sat",
    "com_sat",
    "rel_sat",
    "aut_fru",
    "com_fru",
    "rel_fru",
    "auth_pr",
    "hubr_pr"
) -> col_nms

raw %>%
    dplyr::rename_with(function(.x) col_nms) %>%
    dplyr::mutate(
        need_sat = rowMeans(dplyr::select(., ends_with("_sat"))),
        need_fru = rowMeans(dplyr::select(., ends_with("_fru")))
    ) -> dat
dat
summary(dat)

c(
    "down_soc",
    "up_soc",
    "down_tem",
    "up_tem",
    "need_sat",
    "need_fru",
    "auth_pr",
    "hubr_pr",
    "ocb_ch"
) -> var_nms

# * calculate mean and sd across variables
dat %>%
    dplyr::select(all_of(var_nms)) %>%
    dplyr::summarise(
        across(
            everything(),
            list(mean = mean, sd = sd)
        )
    ) %>%
    tidyr::pivot_longer(col = everything(), names_to = "stat_type") %>%
    tidyr::separate(stat_type, into = c("var", "stat"), sep = "_mean|_sd") %>%
    dplyr::mutate(stat = rep(c("mean", "sd"), 9)) %>%
    tidyr::pivot_wider(names_from = stat, values_from = value) -> mean_sd_df
mean_sd_df

# * function to calc icc and extract from list
icc_calc <- function(var) {
    mod <- lme4::lmer(var ~ 1 + (1 | id), data = dat)
    performance::icc(mod) |>
        unlist()
}

# * placing iccs in df
dat %>%
    select(
        ends_with("_soc"),
        ends_with("_tem"),
        starts_with("need_"),
        ends_with("_pr"),
        ocb_ch
    ) %>%
    sapply(., function(.x) icc_calc(.x)) %>%
    as.data.frame() %>%
    dplyr::slice(1) %>%
    tidyr::pivot_longer(
        cols = everything(),
        names_to = "var",
        values_to = "icc"
    ) -> icc_df
icc_df

# * calc cors for vars
rmcorr::rmcorr_mat(
    participant = "id",
    variables = var_nms,
    dataset = dat,
    CI.level = 0.95
)[[1]] -> wp_cors
wp_cors

# hide lower triangle
round(wp_cors, 2) -> lower
"" -> lower[lower.tri(wp_cors, diag = TRUE)]
lower %>%
    tibble::as_tibble(rownames = "var") -> lower
lower

dplyr::left_join(mean_sd_df, icc_df, by = c("var" = "var")) %>%
    dplyr::mutate(across(!var, function(.x) round(.x, 2))) %>%
    dplyr::left_join(., lower, by = c("var" = "var"))

## MLCFA
mod05 <- "
level: 1
need_sat =~ aut_sat + com_sat + rel_sat
need_fru =~ aut_fru + com_fru + rel_fru
all =~ aut_sat + com_sat + rel_sat + aut_fru + com_fru + rel_fru + auth_pr + hubr_pr

level: 2
need_sat =~ aut_sat + com_sat + rel_sat
need_fru =~ aut_fru + com_fru + rel_fru
all =~ aut_sat + com_sat + rel_sat + aut_fru + com_fru + rel_fru + auth_pr + hubr_pr"

mod05_out <- cfa(
    mod05,
    cluster = "id",
    data = dat[
        c(
            "id", "aut_sat", "com_sat", "rel_sat", "aut_fru", "com_fru",
            "rel_fru", "auth_pr", "hubr_pr"
        )
    ]
)
summary(mod05_out, fit.measures = TRUE)
