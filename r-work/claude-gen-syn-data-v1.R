# Load required packages
library(MASS)
library(tidyverse)
library(here)

# Set parameters
set.seed(123)
n_participants <- 700
n_timepoints <- 3
total_observations <- n_participants * n_timepoints

# Define target correlation matrix based on meta-analytic evidence
# Variables: pa_score, na_score, pcb_score, pcv_score, job_sat,
# burn_pf_score, burn_cw_score, burn_ee_score,
# nf_comp_score, nf_auto_score, nf_rel_score,
# atcb_score, turnover_int

target_corr_matrix <- matrix(c(
    # PA    NA    PCB   PCV   JS    BPF   BCW   BEE   NFC   NFA   NFR   ATCB  TI
    1.00, -0.50, 0.00, 0.00, 0.30, -0.25, -0.25, -0.25, -0.20, -0.20, -0.20, 0.00, -0.15, # PA
    -0.50, 1.00, 0.15, 0.15, -0.35, 0.40, 0.40, 0.40, 0.35, 0.35, 0.35, 0.00, 0.25, # NA
    0.00, 0.15, 1.00, 0.70, -0.30, 0.35, 0.35, 0.35, 0.30, 0.30, 0.30, 0.00, 0.25, # PCB
    0.00, 0.15, 0.70, 1.00, -0.25, 0.30, 0.30, 0.30, 0.25, 0.25, 0.25, 0.00, 0.20, # PCV
    0.30, -0.35, -0.30, -0.25, 1.00, -0.63, -0.63, -0.63, -0.40, -0.40, -0.40, 0.00, -0.43, # Job Sat
    -0.25, 0.40, 0.35, 0.30, -0.63, 1.00, 0.65, 0.65, 0.50, 0.50, 0.50, 0.00, 0.45, # Burn PF
    -0.25, 0.40, 0.35, 0.30, -0.63, 0.65, 1.00, 0.65, 0.50, 0.50, 0.50, 0.00, 0.45, # Burn CW
    -0.25, 0.40, 0.35, 0.30, -0.63, 0.65, 0.65, 1.00, 0.50, 0.50, 0.50, 0.00, 0.45, # Burn EE
    -0.20, 0.35, 0.30, 0.25, -0.40, 0.50, 0.50, 0.50, 1.00, 0.60, 0.60, 0.00, 0.30, # NF Comp
    -0.20, 0.35, 0.30, 0.25, -0.40, 0.50, 0.50, 0.50, 0.60, 1.00, 0.60, 0.00, 0.30, # NF Auto
    -0.20, 0.35, 0.30, 0.25, -0.40, 0.50, 0.50, 0.50, 0.60, 0.60, 1.00, 0.00, 0.30, # NF Rel
    0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 1.00, 0.00, # ATCB
    -0.15, 0.25, 0.25, 0.20, -0.43, 0.45, 0.45, 0.45, 0.30, 0.30, 0.30, 0.00, 1.00 # Turnover
), nrow = 13, byrow = TRUE)

colnames(target_corr_matrix) <- rownames(target_corr_matrix) <- c(
    "pa_score", "na_score", "pcb_score", "pcv_score", "job_sat",
    "burn_pf_score", "burn_cw_score", "burn_ee_score",
    "nf_comp_score", "nf_auto_score", "nf_rel_score",
    "atcb_score", "turnover_int"
)

# Generate demographics (time-invariant)
demographics <- tibble(
    participant_id = 1:n_participants,
    age = sample(22:65, n_participants, replace = TRUE),
    ethnicity = sample(c(
        "American Indian/Alaska Native", "Asian", "Black/African American",
        "Arab/Middle Eastern/North African", "Hispanic/Latino",
        "Native Hawaiian/Pacific Islander", "White/Caucasian",
        "Two or more", "Prefer not to say"
    ), n_participants, replace = TRUE),
    gender = sample(c("Woman", "Man", "Non-binary", "Other", "Prefer not to say"),
        n_participants,
        replace = TRUE
    ),
    job_tenure = sample(c("<1 year", "1-3 years", "3-5 years", ">5 years"),
        n_participants,
        replace = TRUE
    ),
    education = sample(c(
        "Some high school", "High school diploma", "Some college",
        "Vocational training", "Associate degree", "Bachelor's degree",
        "Master's degree", "Professional/doctorate"
    ), n_participants, replace = TRUE),
    remote_status = sample(c(TRUE, FALSE), n_participants, replace = TRUE)
)

# Generate correlated scale scores using multivariate normal distribution
means <- c(3.5, 2.5, 2.8, 2.5, 3.5, 3.0, 3.0, 2.8, 2.7, 2.7, 2.7, 3.0, 2.5)
sds <- c(0.7, 0.7, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.7, 0.9)

# Create covariance matrix
cov_matrix <- target_corr_matrix * (sds %o% sds)

# Generate base scale scores for each participant (time-invariant component)
base_scores <- mvrnorm(n_participants, mu = means, Sigma = cov_matrix)
colnames(base_scores) <- colnames(target_corr_matrix)

# Function to generate item-level data from scale scores
generate_items <- function(scale_score, n_items, min_val = 1, max_val = 5, noise_sd = 0.3) {
    n_obs <- length(scale_score)
    items <- matrix(NA, nrow = n_obs, ncol = n_items)

    for (i in 1:n_items) {
        items[, i] <- pmax(pmin(round(scale_score + rnorm(n_obs, 0, noise_sd)), max_val), min_val)
    }

    return(items)
}

# Generate TIME-INVARIANT items (measured only once)
# These will be the same across all timepoints
time_invariant_scores <- base_scores[, c("pa_score", "na_score", "pcb_score", "pcv_score", "job_sat")]

# Generate item-level data for time-invariant scales
pa_items_invariant <- generate_items(time_invariant_scores[, "pa_score"], 5)
na_items_invariant <- generate_items(time_invariant_scores[, "na_score"], 5)
pcb_items_invariant <- generate_items(time_invariant_scores[, "pcb_score"], 5)
pcv_items_invariant <- generate_items(time_invariant_scores[, "pcv_score"], 4)
job_sat_invariant <- round(time_invariant_scores[, "job_sat"])

# Create the full multilevel dataset
full_data <- tibble()

for (t in 1:n_timepoints) {
    # For TIME-VARYING variables, add small random variation
    time_varying_vars <- c(
        "burn_pf_score", "burn_cw_score", "burn_ee_score",
        "nf_comp_score", "nf_auto_score", "nf_rel_score",
        "atcb_score", "turnover_int"
    )

    time_variation <- mvrnorm(n_participants,
        mu = rep(0, length(time_varying_vars)),
        Sigma = diag(0.1, length(time_varying_vars))
    )

    current_time_varying_scores <- base_scores[, time_varying_vars] + time_variation

    # Ensure scores stay within reasonable bounds
    current_time_varying_scores <- pmax(pmin(current_time_varying_scores, 5), 1)

    # Generate item-level data for TIME-VARYING scales
    pf_items <- generate_items(current_time_varying_scores[, "burn_pf_score"], 6)
    cw_items <- generate_items(current_time_varying_scores[, "burn_cw_score"], 5)
    ee_items <- generate_items(current_time_varying_scores[, "burn_ee_score"], 3)
    nf_comp_items <- generate_items(current_time_varying_scores[, "nf_comp_score"], 4)
    nf_auto_items <- generate_items(current_time_varying_scores[, "nf_auto_score"], 4)
    nf_rel_items <- generate_items(current_time_varying_scores[, "nf_rel_score"], 4)
    blue_items <- generate_items(current_time_varying_scores[, "atcb_score"], 4)

    # Generate meeting data (time-varying)
    n_meetings <- rpois(n_participants, lambda = 1.2)
    n_meetings <- pmin(n_meetings, 6)
    min_meetings <- ifelse(n_meetings == 0, 0, n_meetings * 30)

    # Create timepoint data
    timepoint_data <- tibble(
        participant_id = 1:n_participants,
        timepoint = t,

        # TIME-INVARIANT PA items (same across all timepoints)
        PA_1 = pa_items_invariant[, 1], PA_2 = pa_items_invariant[, 2], PA_3 = pa_items_invariant[, 3],
        PA_4 = pa_items_invariant[, 4], PA_5 = pa_items_invariant[, 5],

        # TIME-INVARIANT NA items (same across all timepoints)
        NA_1 = na_items_invariant[, 1], NA_2 = na_items_invariant[, 2], NA_3 = na_items_invariant[, 3],
        NA_4 = na_items_invariant[, 4], NA_5 = na_items_invariant[, 5],

        # TIME-INVARIANT PCB items (same across all timepoints)
        PCB_1 = pcb_items_invariant[, 1], PCB_2 = pcb_items_invariant[, 2], PCB_3 = pcb_items_invariant[, 3],
        PCB_4 = pcb_items_invariant[, 4], PCB_5 = pcb_items_invariant[, 5],

        # TIME-INVARIANT PCV items (same across all timepoints)
        PCV_1 = pcv_items_invariant[, 1], PCV_2 = pcv_items_invariant[, 2],
        PCV_3 = pcv_items_invariant[, 3], PCV_4 = pcv_items_invariant[, 4],

        # TIME-INVARIANT job satisfaction (same across all timepoints)
        job_sat = job_sat_invariant,

        # TIME-VARYING Burnout PF items (different across timepoints)
        PF_1 = pf_items[, 1], PF_2 = pf_items[, 2], PF_3 = pf_items[, 3],
        PF_4 = pf_items[, 4], PF_5 = pf_items[, 5], PF_6 = pf_items[, 6],

        # TIME-VARYING Burnout CW items (different across timepoints)
        CW_1 = cw_items[, 1], CW_2 = cw_items[, 2], CW_3 = cw_items[, 3],
        CW_4 = cw_items[, 4], CW_5 = cw_items[, 5],

        # TIME-VARYING Burnout EE items (different across timepoints)
        EE_1 = ee_items[, 1], EE_2 = ee_items[, 2], EE_3 = ee_items[, 3],

        # TIME-VARYING Need Frustration Competence items (different across timepoints)
        NF_Comp_1 = nf_comp_items[, 1], NF_Comp_2 = nf_comp_items[, 2],
        NF_Comp_3 = nf_comp_items[, 3], NF_Comp_4 = nf_comp_items[, 4],

        # TIME-VARYING Need Frustration Autonomy items (different across timepoints)
        NF_Auto_1 = nf_auto_items[, 1], NF_Auto_2 = nf_auto_items[, 2],
        NF_Auto_3 = nf_auto_items[, 3], NF_Auto_4 = nf_auto_items[, 4],

        # TIME-VARYING Need Frustration Relatedness items (different across timepoints)
        NF_Rel_1 = nf_rel_items[, 1], NF_Rel_2 = nf_rel_items[, 2],
        NF_Rel_3 = nf_rel_items[, 3], NF_Rel_4 = nf_rel_items[, 4],

        # TIME-VARYING ATCB (marker variable) items (different across timepoints)
        Blue_1 = blue_items[, 1], Blue_2 = blue_items[, 2],
        Blue_3 = blue_items[, 3], Blue_4 = blue_items[, 4],

        # TIME-VARYING turnover intention (different across timepoints)
        turnover_int = round(current_time_varying_scores[, "turnover_int"]),

        # TIME-VARYING meeting variables (different across timepoints)
        n_meetings = n_meetings,
        min_meetings = min_meetings
    ) %>%
        # Add demographics
        left_join(demographics, by = "participant_id")

    full_data <- bind_rows(full_data, timepoint_data)
}

# Save the dataset
full_data %>%
    dplyr::arrange(participant_id) %>%
    readr::write_csv(., here("r-work", "claude-syn-data-raw.csv"))

# Verification: Check that time-invariant variables are actually invariant
cat("Verification: Checking time-invariant variables...\n")

# Check PA items across timepoints for first 5 participants
verification_data <- full_data %>%
    filter(participant_id <= 5) %>%
    select(participant_id, timepoint, PA_1, NA_1, PCB_1, PCV_1, job_sat) %>%
    arrange(participant_id, timepoint)

print(verification_data)

cat("\nDataset created with", nrow(full_data), "observations\n")
cat("Time-invariant variables (PA, NA, PCB, PCV, job_sat) are now constant across timepoints\n")
cat("Time-varying variables (burnout, need frustration, meetings, turnover) vary across timepoints\n")

# !!!
# # Load required packages
# library(MASS)
# library(tidyverse)
# library(here)

# # Set parameters
# set.seed(123)
# n_participants <- 700
# n_timepoints <- 3
# total_observations <- n_participants * n_timepoints

# # Define target correlation matrix based on meta-analytic evidence
# # Variables: pa_score, na_score, pcb_score, pcv_score, job_sat,
# #           burn_pf_score, burn_cw_score, burn_ee_score,
# #           nf_comp_score, nf_auto_score, nf_rel_score,
# #           atcb_score, turnover_int

# target_corr_matrix <- matrix(c(
#     # PA    NA    PCB   PCV   JS    BPF   BCW   BEE   NFC   NFA   NFR   ATCB  TI
#     1.00, -0.50, 0.00, 0.00, 0.30, -0.25, -0.25, -0.25, -0.20, -0.20, -0.20, 0.00, -0.15, # PA
#     -0.50, 1.00, 0.15, 0.15, -0.35, 0.40, 0.40, 0.40, 0.35, 0.35, 0.35, 0.00, 0.25, # NA
#     0.00, 0.15, 1.00, 0.70, -0.30, 0.35, 0.35, 0.35, 0.30, 0.30, 0.30, 0.00, 0.25, # PCB
#     0.00, 0.15, 0.70, 1.00, -0.25, 0.30, 0.30, 0.30, 0.25, 0.25, 0.25, 0.00, 0.20, # PCV
#     0.30, -0.35, -0.30, -0.25, 1.00, -0.63, -0.63, -0.63, -0.40, -0.40, -0.40, 0.00, -0.43, # Job Sat
#     -0.25, 0.40, 0.35, 0.30, -0.63, 1.00, 0.65, 0.65, 0.50, 0.50, 0.50, 0.00, 0.45, # Burn PF
#     -0.25, 0.40, 0.35, 0.30, -0.63, 0.65, 1.00, 0.65, 0.50, 0.50, 0.50, 0.00, 0.45, # Burn CW
#     -0.25, 0.40, 0.35, 0.30, -0.63, 0.65, 0.65, 1.00, 0.50, 0.50, 0.50, 0.00, 0.45, # Burn EE
#     -0.20, 0.35, 0.30, 0.25, -0.40, 0.50, 0.50, 0.50, 1.00, 0.60, 0.60, 0.00, 0.30, # NF Comp
#     -0.20, 0.35, 0.30, 0.25, -0.40, 0.50, 0.50, 0.50, 0.60, 1.00, 0.60, 0.00, 0.30, # NF Auto
#     -0.20, 0.35, 0.30, 0.25, -0.40, 0.50, 0.50, 0.50, 0.60, 0.60, 1.00, 0.00, 0.30, # NF Rel
#     0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 1.00, 0.00, # ATCB
#     -0.15, 0.25, 0.25, 0.20, -0.43, 0.45, 0.45, 0.45, 0.30, 0.30, 0.30, 0.00, 1.00 # Turnover
# ), nrow = 13, byrow = TRUE)

# colnames(target_corr_matrix) <- rownames(target_corr_matrix) <- c(
#     "pa_score", "na_score", "pcb_score", "pcv_score", "job_sat",
#     "burn_pf_score", "burn_cw_score", "burn_ee_score",
#     "nf_comp_score", "nf_auto_score", "nf_rel_score",
#     "atcb_score", "turnover_int"
# )

# # Generate demographics (time-invariant)
# demographics <- tibble(
#     participant_id = 1:n_participants,
#     age = sample(22:65, n_participants, replace = TRUE),
#     ethnicity = sample(c(
#         "American Indian/Alaska Native", "Asian", "Black/African American",
#         "Arab/Middle Eastern/North African", "Hispanic/Latino",
#         "Native Hawaiian/Pacific Islander", "White/Caucasian",
#         "Two or more", "Prefer not to say"
#     ), n_participants, replace = TRUE),
#     gender = sample(c("Woman", "Man", "Non-binary", "Other", "Prefer not to say"),
#         n_participants,
#         replace = TRUE
#     ),
#     job_tenure = sample(c("<1 year", "1-3 years", "3-5 years", ">5 years"),
#         n_participants,
#         replace = TRUE
#     ),
#     education = sample(c(
#         "Some high school", "High school diploma", "Some college",
#         "Vocational training", "Associate degree", "Bachelor's degree",
#         "Master's degree", "Professional/doctorate"
#     ), n_participants, replace = TRUE),
#     remote_status = sample(c(TRUE, FALSE), n_participants, replace = TRUE)
# )

# # Generate correlated scale scores using multivariate normal distribution
# means <- c(3.5, 2.5, 2.8, 2.5, 3.5, 3.0, 3.0, 2.8, 2.7, 2.7, 2.7, 3.0, 2.5)
# sds <- c(0.7, 0.7, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.7, 0.9)

# # Create covariance matrix
# cov_matrix <- target_corr_matrix * (sds %o% sds)

# # Generate base scale scores for each participant (time-invariant component)
# base_scores <- mvrnorm(n_participants, mu = means, Sigma = cov_matrix)
# colnames(base_scores) <- colnames(target_corr_matrix)

# # Function to generate item-level data from scale scores
# generate_items <- function(scale_score, n_items, min_val = 1, max_val = 5, noise_sd = 0.3) {
#     n_obs <- length(scale_score)
#     items <- matrix(NA, nrow = n_obs, ncol = n_items)

#     for (i in 1:n_items) {
#         items[, i] <- pmax(pmin(round(scale_score + rnorm(n_obs, 0, noise_sd)), max_val), min_val)
#     }

#     return(items)
# }

# # Create the full multilevel dataset
# full_data <- tibble()

# for (t in 1:n_timepoints) {
#     # Add small random variation for time-varying effects
#     time_variation <- mvrnorm(n_participants, mu = rep(0, 13), Sigma = diag(0.1, 13))
#     current_scores <- base_scores + time_variation

#     # Ensure scores stay within reasonable bounds
#     current_scores <- pmax(pmin(current_scores, 5), 1)

#     # Generate item-level data for each scale
#     pa_items <- generate_items(current_scores[, "pa_score"], 5)
#     na_items <- generate_items(current_scores[, "na_score"], 5)
#     pcb_items <- generate_items(current_scores[, "pcb_score"], 5)
#     pcv_items <- generate_items(current_scores[, "pcv_score"], 4)
#     pf_items <- generate_items(current_scores[, "burn_pf_score"], 6)
#     cw_items <- generate_items(current_scores[, "burn_cw_score"], 5)
#     ee_items <- generate_items(current_scores[, "burn_ee_score"], 3)
#     nf_comp_items <- generate_items(current_scores[, "nf_comp_score"], 4)
#     nf_auto_items <- generate_items(current_scores[, "nf_auto_score"], 4)
#     nf_rel_items <- generate_items(current_scores[, "nf_rel_score"], 4)
#     blue_items <- generate_items(current_scores[, "atcb_score"], 4)

#     # Generate meeting data
#     n_meetings <- rpois(n_participants, lambda = 1.2)
#     n_meetings <- pmin(n_meetings, 6)
#     min_meetings <- ifelse(n_meetings == 0, 0, n_meetings * 30)

#     # Create timepoint data
#     timepoint_data <- tibble(
#         participant_id = 1:n_participants,
#         timepoint = t,
#         # PA items
#         PA_1 = pa_items[, 1], PA_2 = pa_items[, 2], PA_3 = pa_items[, 3],
#         PA_4 = pa_items[, 4], PA_5 = pa_items[, 5],
#         # NA items
#         NA_1 = na_items[, 1], NA_2 = na_items[, 2], NA_3 = na_items[, 3],
#         NA_4 = na_items[, 4], NA_5 = na_items[, 5],
#         # PCB items
#         PCB_1 = pcb_items[, 1], PCB_2 = pcb_items[, 2], PCB_3 = pcb_items[, 3],
#         PCB_4 = pcb_items[, 4], PCB_5 = pcb_items[, 5],
#         # PCV items
#         PCV_1 = pcv_items[, 1], PCV_2 = pcv_items[, 2],
#         PCV_3 = pcv_items[, 3], PCV_4 = pcv_items[, 4],
#         # Burnout PF items
#         PF_1 = pf_items[, 1], PF_2 = pf_items[, 2], PF_3 = pf_items[, 3],
#         PF_4 = pf_items[, 4], PF_5 = pf_items[, 5], PF_6 = pf_items[, 6],
#         # Burnout CW items
#         CW_1 = cw_items[, 1], CW_2 = cw_items[, 2], CW_3 = cw_items[, 3],
#         CW_4 = cw_items[, 4], CW_5 = cw_items[, 5],
#         # Burnout EE items
#         EE_1 = ee_items[, 1], EE_2 = ee_items[, 2], EE_3 = ee_items[, 3],
#         # Need Frustration Competence items
#         NF_Comp_1 = nf_comp_items[, 1], NF_Comp_2 = nf_comp_items[, 2],
#         NF_Comp_3 = nf_comp_items[, 3], NF_Comp_4 = nf_comp_items[, 4],
#         # Need Frustration Autonomy items
#         NF_Auto_1 = nf_auto_items[, 1], NF_Auto_2 = nf_auto_items[, 2],
#         NF_Auto_3 = nf_auto_items[, 3], NF_Auto_4 = nf_auto_items[, 4],
#         # Need Frustration Relatedness items
#         NF_Rel_1 = nf_rel_items[, 1], NF_Rel_2 = nf_rel_items[, 2],
#         NF_Rel_3 = nf_rel_items[, 3], NF_Rel_4 = nf_rel_items[, 4],
#         # ATCB (marker variable) items
#         Blue_1 = blue_items[, 1], Blue_2 = blue_items[, 2],
#         Blue_3 = blue_items[, 3], Blue_4 = blue_items[, 4],
#         # Single item measures
#         job_sat = round(current_scores[, "job_sat"]),
#         turnover_int = round(current_scores[, "turnover_int"]),
#         # Meeting variables
#         n_meetings = n_meetings,
#         min_meetings = min_meetings
#     ) %>%
#         # Add demographics
#         left_join(demographics, by = "participant_id")

#     full_data <- bind_rows(full_data, timepoint_data)
# }

# # Save the dataset
# full_data %>%
#     dplyr::arrange(participant_id) %>%
#     readr::write_csv(., here("r-work", "claude-syn-data-raw.csv"))

# # # Verify the correlations using your existing analysis code
# # full_data %>%
# #     rename_all(tolower) %>%
# #     mutate(
# #         id = str_pad(as.character(participant_id), width = 3, pad = "0"),
# #         time = timepoint - 1,
# #         time_fct = as_factor(time),
# #         ethnicity = as_factor(ethnicity),
# #         gender = as_factor(gender),
# #         job_tenure = as_factor(job_tenure),
# #         edu = as_factor(education),
# #         work_loc = as_factor(if_else(remote_status == TRUE, "Remote", "In-office")),
# #         pa_score = rowMeans(select(., starts_with("pa_")), na.rm = TRUE),
# #         na_score = rowMeans(select(., starts_with("na_")), na.rm = TRUE),
# #         pcb_score = rowMeans(select(., starts_with("pcb_")), na.rm = TRUE),
# #         pcv_score = rowMeans(select(., starts_with("pcv_")), na.rm = TRUE),
# #         burn_pf_score = rowMeans(select(., starts_with("pf_")), na.rm = TRUE),
# #         burn_cw_score = rowMeans(select(., starts_with("cw_")), na.rm = TRUE),
# #         burn_ee_score = rowMeans(select(., starts_with("ee_")), na.rm = TRUE),
# #         nf_comp_score = rowMeans(select(., starts_with("nf_comp")), na.rm = TRUE),
# #         nf_auto_score = rowMeans(select(., starts_with("nf_auto")), na.rm = TRUE),
# #         nf_rel_score = rowMeans(select(., starts_with("nf_rel")), na.rm = TRUE),
# #         atcb_score = rowMeans(select(., starts_with("blue_")), na.rm = TRUE)
# #     ) %>%
# #     dplyr::arrange(id) %>%
# #     select(
# #         id,
# #         time,
# #         time_fct,
# #         age,
# #         ethnicity,
# #         gender,
# #         job_tenure,
# #         edu,
# #         work_loc,
# #         pa_score,
# #         na_score,
# #         pcb_score,
# #         pcv_score,
# #         job_sat,
# #         burn_pf_score,
# #         burn_cw_score,
# #         burn_ee_score,
# #         nf_comp_score,
# #         nf_auto_score,
# #         nf_rel_score,
# #         atcb_score,
# #         n_meetings,
# #         min_meetings,
# #         turnover_int
# #     )

# # # Display correlation matrix to verify results
# # cat("Generated correlation matrix:\n")
# # study_vars_dat %>%
# #     select(pa_score:turnover_int) %>%
# #     cor() %>%
# #     round(3) %>%
# #     print()

# # cat("\nDataset created with", nrow(full_data), "observations\n")
# # cat("Variables match your analysis pipeline requirements\n")
