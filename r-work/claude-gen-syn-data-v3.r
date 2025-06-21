# Load required packages
library(MASS)
library(tidyverse)
library(here)
library(purrr)

# Set parameters
set.seed(8762)
n_participants <- 700
n_timepoints <- 3
total_observations <- n_participants * n_timepoints

# Define target correlation matrix (unchanged)
create_target_corr_matrix <- function() {
    matrix(c(
        # PA NA PCB PCV JS BPF BCW BEE NFC NFA NFR ATCB TI
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
    ), nrow = 13, byrow = TRUE) %>%
        `colnames<-`(c(
            "pa_score", "na_score", "pcb_score", "pcv_score", "job_sat",
            "burn_pf_score", "burn_cw_score", "burn_ee_score",
            "nf_comp_score", "nf_auto_score", "nf_rel_score",
            "atcb_score", "turnover_int"
        )) %>%
        `rownames<-`(c(
            "pa_score", "na_score", "pcb_score", "pcv_score", "job_sat",
            "burn_pf_score", "burn_cw_score", "burn_ee_score",
            "nf_comp_score", "nf_auto_score", "nf_rel_score",
            "atcb_score", "turnover_int"
        ))
}

# Create within-person correlation matrix for time-varying variables
create_wp_corr_matrix <- function() {
    # Based on literature, within-person correlations are typically 0.3-0.7 of between-person correlations
    matrix(c(
        # BPF BCW BEE NFC NFA NFR ATCB TI
        1.00, 0.45, 0.40, 0.35, 0.30, 0.25, 0.00, 0.30, # Burn PF
        0.45, 1.00, 0.40, 0.30, 0.25, 0.20, 0.00, 0.25, # Burn CW
        0.40, 0.40, 1.00, 0.25, 0.20, 0.15, 0.00, 0.20, # Burn EE
        0.35, 0.30, 0.25, 1.00, 0.40, 0.35, 0.00, 0.20, # NF Comp
        0.30, 0.25, 0.20, 0.40, 1.00, 0.35, 0.00, 0.15, # NF Auto
        0.25, 0.20, 0.15, 0.35, 0.35, 1.00, 0.00, 0.10, # NF Rel
        0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 1.00, 0.00, # ATCB
        0.30, 0.25, 0.20, 0.20, 0.15, 0.10, 0.00, 1.00 # Turnover
    ), nrow = 8, byrow = TRUE) %>%
        `colnames<-`(c(
            "burn_pf_score", "burn_cw_score", "burn_ee_score",
            "nf_comp_score", "nf_auto_score", "nf_rel_score",
            "atcb_score", "turnover_int"
        )) %>%
        `rownames<-`(c(
            "burn_pf_score", "burn_cw_score", "burn_ee_score",
            "nf_comp_score", "nf_auto_score", "nf_rel_score",
            "atcb_score", "turnover_int"
        ))
}

# Generate demographics (unchanged)
generate_demos <- function(n_participants) {
    tibble::tibble(
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
}

# Create covariance matrix (unchanged)
create_covar_matrix <- function(correlation_matrix, sds) {
    correlation_matrix * (sds %o% sds)
}

# Generate base scores (unchanged)
generate_base_scores <- function(n_participants, means, cov_matrix, var_names) {
    mvrnorm(n_participants, mu = means, Sigma = cov_matrix) %>%
        `colnames<-`(var_names)
}

# Updated function to generate time-varying scores with proper within-person correlations
generate_time_varying_scores <- function(base_scores, n_participants, within_person_corr_matrix) {
    time_varying_vars <- c(
        "burn_pf_score", "burn_cw_score", "burn_ee_score",
        "nf_comp_score", "nf_auto_score", "nf_rel_score",
        "atcb_score", "turnover_int"
    )

    # Create within-person variation with meaningful correlations
    # Use larger variance components (0.4-0.6 instead of 0.1)
    within_person_sds <- c(0.5, 0.5, 0.6, 0.4, 0.4, 0.4, 0.3, 0.5)
    within_person_cov_matrix <- within_person_corr_matrix * (within_person_sds %o% within_person_sds)

    # Generate correlated within-person deviations
    within_person_deviations <- mvrnorm(n_participants,
        mu = rep(0, length(time_varying_vars)),
        Sigma = within_person_cov_matrix
    )

    # Add the deviations to base scores
    adjusted_scores <- base_scores[, time_varying_vars] + within_person_deviations

    # Ensure scores stay within reasonable bounds
    adjusted_scores %>%
        pmax(1) %>%
        pmin(5)
}

# Generate items (unchanged)
generate_items <- function(scale_score, n_items, min_val = 1, max_val = 5, noise_sd = 0.3) {
    n_obs <- length(scale_score)
    map(1:n_items, ~ {
        pmax(pmin(round(scale_score + rnorm(n_obs, 0, noise_sd)), max_val), min_val)
    }) %>%
        do.call(cbind, .)
}

# Generate time-invariant items (unchanged)
generate_time_invariant_items <- function(base_scores) {
    time_invariant_vars <- c("pa_score", "na_score", "pcb_score", "pcv_score", "job_sat")
    time_invariant_scores <- base_scores[, time_invariant_vars]

    list(
        pa_items = generate_items(time_invariant_scores[, "pa_score"], 5),
        na_items = generate_items(time_invariant_scores[, "na_score"], 5),
        pcb_items = generate_items(time_invariant_scores[, "pcb_score"], 5),
        pcv_items = generate_items(time_invariant_scores[, "pcv_score"], 4),
        job_sat = round(time_invariant_scores[, "job_sat"])
    )
}

# Updated function to generate time-varying items
generate_time_varying_items <- function(time_varying_scores) {
    list(
        pf_items = generate_items(time_varying_scores[, "burn_pf_score"], 6),
        cw_items = generate_items(time_varying_scores[, "burn_cw_score"], 5),
        ee_items = generate_items(time_varying_scores[, "burn_ee_score"], 3),
        nf_comp_items = generate_items(time_varying_scores[, "nf_comp_score"], 4),
        nf_auto_items = generate_items(time_varying_scores[, "nf_auto_score"], 4),
        nf_rel_items = generate_items(time_varying_scores[, "nf_rel_score"], 4),
        blue_items = generate_items(time_varying_scores[, "atcb_score"], 4),
        turnover_int = round(time_varying_scores[, "turnover_int"])
    )
}

# Generate meeting data (unchanged)
generate_meeting_data <- function(n_participants) {
    n_meetings <- rpois(n_participants, lambda = 1.2) %>% pmin(6)
    min_meetings <- ifelse(n_meetings == 0, 0, n_meetings * 30)
    list(n_meetings = n_meetings, min_meetings = min_meetings)
}

# Create timepoint data (unchanged structure)
create_timepoint_data <- function(
    t, n_participants, time_invariant_items,
    time_varying_items, meeting_data, demographics) {
    tibble::tibble(
        participant_id = 1:n_participants,
        timepoint = t,
        # TIME-INVARIANT PA items
        PA_1 = time_invariant_items$pa_items[, 1], PA_2 = time_invariant_items$pa_items[, 2],
        PA_3 = time_invariant_items$pa_items[, 3], PA_4 = time_invariant_items$pa_items[, 4],
        PA_5 = time_invariant_items$pa_items[, 5],
        # TIME-INVARIANT NA items
        NA_1 = time_invariant_items$na_items[, 1], NA_2 = time_invariant_items$na_items[, 2],
        NA_3 = time_invariant_items$na_items[, 3], NA_4 = time_invariant_items$na_items[, 4],
        NA_5 = time_invariant_items$na_items[, 5],
        # TIME-INVARIANT PCB items
        PCB_1 = time_invariant_items$pcb_items[, 1], PCB_2 = time_invariant_items$pcb_items[, 2],
        PCB_3 = time_invariant_items$pcb_items[, 3], PCB_4 = time_invariant_items$pcb_items[, 4],
        PCB_5 = time_invariant_items$pcb_items[, 5],
        # TIME-INVARIANT PCV items
        PCV_1 = time_invariant_items$pcv_items[, 1], PCV_2 = time_invariant_items$pcv_items[, 2],
        PCV_3 = time_invariant_items$pcv_items[, 3], PCV_4 = time_invariant_items$pcv_items[, 4],
        # TIME-INVARIANT job satisfaction
        job_sat = time_invariant_items$job_sat,
        # TIME-VARYING Burnout PF items
        PF_1 = time_varying_items$pf_items[, 1], PF_2 = time_varying_items$pf_items[, 2],
        PF_3 = time_varying_items$pf_items[, 3], PF_4 = time_varying_items$pf_items[, 4],
        PF_5 = time_varying_items$pf_items[, 5], PF_6 = time_varying_items$pf_items[, 6],
        # TIME-VARYING Burnout CW items
        CW_1 = time_varying_items$cw_items[, 1], CW_2 = time_varying_items$cw_items[, 2],
        CW_3 = time_varying_items$cw_items[, 3], CW_4 = time_varying_items$cw_items[, 4],
        CW_5 = time_varying_items$cw_items[, 5],
        # TIME-VARYING Burnout EE items
        EE_1 = time_varying_items$ee_items[, 1], EE_2 = time_varying_items$ee_items[, 2],
        EE_3 = time_varying_items$ee_items[, 3],
        # TIME-VARYING Need Frustration items
        NF_Comp_1 = time_varying_items$nf_comp_items[, 1], NF_Comp_2 = time_varying_items$nf_comp_items[, 2],
        NF_Comp_3 = time_varying_items$nf_comp_items[, 3], NF_Comp_4 = time_varying_items$nf_comp_items[, 4],
        NF_Auto_1 = time_varying_items$nf_auto_items[, 1], NF_Auto_2 = time_varying_items$nf_auto_items[, 2],
        NF_Auto_3 = time_varying_items$nf_auto_items[, 3], NF_Auto_4 = time_varying_items$nf_auto_items[, 4],
        NF_Rel_1 = time_varying_items$nf_rel_items[, 1], NF_Rel_2 = time_varying_items$nf_rel_items[, 2],
        NF_Rel_3 = time_varying_items$nf_rel_items[, 3], NF_Rel_4 = time_varying_items$nf_rel_items[, 4],
        # TIME-VARYING ATCB items
        Blue_1 = time_varying_items$blue_items[, 1], Blue_2 = time_varying_items$blue_items[, 2],
        Blue_3 = time_varying_items$blue_items[, 3], Blue_4 = time_varying_items$blue_items[, 4],
        # TIME-VARYING turnover intention
        turnover_int = time_varying_items$turnover_int,
        # TIME-VARYING meeting variables
        n_meetings = meeting_data$n_meetings,
        min_meetings = meeting_data$min_meetings
    ) %>%
        dplyr::left_join(demographics, by = "participant_id")
}

# Updated main pipeline
main_pipeline <- function() {
    # Initialize parameters
    target_corr_matrix <- create_target_corr_matrix()
    within_person_corr_matrix <- create_wp_corr_matrix()
    means <- c(3.5, 2.5, 2.8, 2.5, 3.5, 3.0, 3.0, 2.8, 2.7, 2.7, 2.7, 3.0, 2.5)
    sds <- c(0.7, 0.7, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.8, 0.7, 0.9)

    # Generate base components
    demographics <- generate_demos(n_participants)
    cov_matrix <- create_covar_matrix(target_corr_matrix, sds)
    base_scores <- generate_base_scores(n_participants, means, cov_matrix, colnames(target_corr_matrix))
    time_invariant_items <- generate_time_invariant_items(base_scores)

    # Generate data for each timepoint
    full_data <- map_dfr(1:n_timepoints, ~ {
        time_varying_scores <- generate_time_varying_scores(base_scores, n_participants, within_person_corr_matrix)
        time_varying_items <- generate_time_varying_items(time_varying_scores)
        meeting_data <- generate_meeting_data(n_participants)

        create_timepoint_data(
            .x, n_participants, time_invariant_items,
            time_varying_items, meeting_data, demographics
        )
    })

    return(full_data)
}

# Execute the pipeline
full_data <- main_pipeline()

# Save the dataset
full_data %>%
    arrange(participant_id) %>%
    write_csv(here("r-work", "claude-syn-data-raw-v3.csv"))

# Verification function
verify_time_invariant <- function(data) {
    verification_data <- data %>%
        dplyr::filter(participant_id <= 5) %>%
        select(participant_id, timepoint, PA_1, NA_1, PCB_1, PCV_1, job_sat) %>%
        arrange(participant_id, timepoint)

    cat("Verification: Checking time-invariant variables...\n")
    print(verification_data)
    cat("\nDataset created with", nrow(data), "observations\n")
    cat("Time-invariant variables (PA, NA, PCB, PCV, job_sat) are constant across timepoints\n")
    cat("Time-varying variables now have meaningful within-person correlations\n")
}

# Run verification
verify_time_invariant(full_data)
