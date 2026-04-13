#!/usr/bin/env python3
"""
generate_synthetic_data.py

Generates psychologically calibrated synthetic ESM data for the PhD dissertation
on within-person fluctuation in burnout, need frustration, and turnover intentions.

Replaces syn_intake_responses_infra.sh and syn_followup_responses_infra.sh.
The int_*.sql and fct_*.sql BigQuery pipeline runs unchanged downstream.

Design targets
--------------
Intake (L2, N=800 participants):
  PA, NA, BR, VIO, JS — L2 between-person scales
  Correlation targets grounded in literature (Watson & Clark 1994; Robinson &
  Morrison 2000; Morrison & Robinson 1997; Kaplan et al. 2009).

Followup (L1, N=800 x 3 timepoints):
  SMBM burnout (PF, CW, EE), PNTS need frustration (NF_COMP, NF_AUTO, NF_RELT),
  ATCB marker, meetings (count + minutes), turnover intention (TI).
  Multilevel simulation: each construct = sqrt(ICC)*BP + sqrt(1-ICC)*WP.
  ICC range .30-.60, targeting the power analysis medium scenario (ICC~.40).
  Within-person NF->TI and burnout->TI effects embedded at medium strength
  (standardized beta ~.25-.30 per facet, composite ~.30).

Effect size reference: dissertation power analysis grid (effect=.30, ICC=.30-.50).
Correlation references: Sonnentag (2018); Schuler et al. (2019); Vahle-Hinz et al.
  (2021); Arend & Schafer (2019).

Usage
-----
    poetry run python analysis/run_synthetic_data/scripts/generate_synthetic_data.py
    poetry run python analysis/run_synthetic_data/scripts/generate_synthetic_data.py --load-bq

Outputs (overwrites existing import files):
    analysis/run_synthetic_data/data/import/claude_gen_syn_intake_responses_20260223.csv
    analysis/run_synthetic_data/data/import/claude_gen_syn_followup_responses_20260223.csv
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.stats import norm

# =============================================================================
# [0] CONSTANTS
# =============================================================================

SEED = 42
RNG = np.random.default_rng(SEED)

N_PARTICIPANTS = 800
N_TIMEPOINTS = 3

SCRIPT_DIR = Path(__file__).parent.resolve()
IMPORT_DIR = SCRIPT_DIR.parent / "data" / "import"
INTAKE_CSV = IMPORT_DIR / "claude_gen_syn_intake_responses_20260223.csv"
FOLLOWUP_CSV = IMPORT_DIR / "claude_gen_syn_followup_responses_20260223.csv"

BQ_PROJECT = "dkg-phd-thesis"
BQ_DATASET = "syn_qualtrics"

# Attention-check answers tied to each timepoint's survey ID (must match SQL)
FOLLOWUP_SURVEY_IDS = {
    1: "SV_5nV942MJGubDmqq",  # 9AM   — attention_check = "Once"
    2: "SV_eRKl4lgMZDAurT8",  # 1PM   — attention_check = "Strongly agree"
    3: "SV_6J3svun1r97AAHc",  # 5PM   — attention_check = "Strongly disagree"
}

# =============================================================================
# [1] LIKERT LABEL ARRAYS  (index 0 = numeric 1)
# =============================================================================

# Intake: I-PANAS-SF frequency scale (PA, NA)
INTAKE_FREQ = [
    "Never",
    "Rather infrequently",
    "Some of the time",
    "Quite often",
    "Always",
]

# Agreement scale used for: intake BR, VIO, JS; followup NF subs, ATCB
AGREE = [
    "Strongly disagree",
    "Disagree",
    "Neither agree nor disagree",
    "Agree",
    "Strongly agree",
]

# Followup: SMBM frequency scale (PF, CW, EE) and TI single item
FOLLOWUP_FREQ = [
    "Never",
    "Once",
    "Twice",
    "Three times",
    "More than three times",
]

# =============================================================================
# [2] LIKERT THRESHOLDS
# =============================================================================
# Each threshold list has len(labels)-1 = 4 breakpoints on the standard normal
# scale.  A continuous score s maps to labels[k] when THRESH[k-1] < s <= THRESH[k].
# Thresholds = norm.ppf(cumulative category probabilities).


def _thr(cumprobs: list[float]) -> list[float]:
    return [float(norm.ppf(p)) for p in cumprobs]


# SMBM frequency: right-skewed, low means typical for within-day ESM
THRESH_PF = _thr([0.33, 0.69, 0.87, 0.96])  # M ~ 2.2 (PF)
THRESH_CW = _thr([0.38, 0.73, 0.89, 0.97])  # M ~ 2.0 (CW)
THRESH_EE = _thr([0.43, 0.76, 0.90, 0.97])  # M ~ 1.8 (EE)

# PNTS agreement: right-skewed, most employees not severely frustrated
THRESH_NF_COMP = _thr([0.27, 0.64, 0.88, 0.97])  # M ~ 2.3
THRESH_NF_AUTO = _thr([0.23, 0.59, 0.85, 0.97])  # M ~ 2.4
THRESH_NF_RELT = _thr([0.32, 0.70, 0.91, 0.98])  # M ~ 2.0

# TI single item (SMBM frequency anchors): very low, most employees rarely want to leave mid-day
THRESH_TI = _thr([0.40, 0.78, 0.94, 0.99])  # M ~ 1.9

# ATCB marker (agreement): near midpoint, uncorrelated with study variables
THRESH_ATCB = _thr([0.10, 0.33, 0.63, 0.90])  # M ~ 2.8

# Intake PA frequency: positive skew (high scores for working adults)
THRESH_PA = _thr([0.02, 0.15, 0.50, 0.85])  # M ~ 3.4

# Intake NA frequency: right-skewed (low NA at baseline)
THRESH_NA_INTAKE = _thr([0.45, 0.74, 0.92, 0.99])  # M ~ 1.9

# Intake PC breach agreement: right-skewed (most perceive low breach)
THRESH_BR = _thr([0.27, 0.61, 0.89, 0.98])  # M ~ 2.3

# Intake PC violation: slightly more right-skewed than breach
THRESH_VIO = _thr([0.34, 0.69, 0.89, 0.98])  # M ~ 2.0

# Intake job satisfaction: positive skew (most workers moderately satisfied)
THRESH_JS = _thr([0.03, 0.12, 0.42, 0.80])  # M ~ 3.6

# =============================================================================
# [3] FACTOR LOADINGS
# =============================================================================
# item = lambda * construct + sqrt(1 - lambda^2) * unique_noise
# Well-validated ESM scales: loadings .70-.82

LOADINGS: dict[str, list[float]] = {
    # L1 SMBM/PNTS: raised to .80-.88 to reduce Likert-discretization attenuation
    # on composite Pearson correlations (see Simulation Notes in module docstring).
    "pf": [0.84, 0.82, 0.80, 0.83, 0.81, 0.82],  # 6 SMBM-PF items
    "cw": [0.83, 0.82, 0.81, 0.80, 0.84],  # 5 SMBM-CW items
    "ee": [0.86, 0.85, 0.87],  # 3 SMBM-EE items
    "comp": [0.81, 0.82, 0.80, 0.83],  # 4 PNTS-competence items
    "auto": [0.83, 0.82, 0.84, 0.81],  # 4 PNTS-autonomy items
    "relt": [0.80, 0.82, 0.81, 0.83],  # 4 PNTS-relatedness items
    "atcb": [0.62, 0.64, 0.63, 0.65],  # 4 ATCB marker items (noisier by design)
    # L2 intake: raised to .83-.88 for same reason
    "pa": [0.84, 0.85, 0.83, 0.86, 0.84],  # 5 I-PANAS-SF PA items
    "na": [0.85, 0.84, 0.86, 0.83, 0.85],  # 5 I-PANAS-SF NA items
    "br": [0.85, 0.86, 0.84, 0.87, 0.85],  # 5 PC breach items
    "vio": [0.88, 0.87, 0.89, 0.86],  # 4 PC violation items
}

# =============================================================================
# [4] CORRELATION MATRICES
# =============================================================================

# --- L2 (intake) correlation matrix: PA, NA, BR, VIO, JS ---
#
# Ordering: PA(0), NA(1), BR(2), VIO(3), JS(4)
#
# Literature sources:
#   r(PA, NA)  ~ -.40  Watson & Clark (1994) — discriminant validity of PANAS
#   r(BR, VIO) ~ .70   Robinson & Morrison (2000) — convergent validity
#   r(BR, JS)  ~ -.45  Morrison & Robinson (1997) — breach -> dissatisfaction
#   r(NA, BR)  ~ .40   negative affect biases breach perceptions
#   r(PA, JS)  ~ .45   positive affect and job satisfaction (Kaplan et al. 2009)

L2_CORR = np.array(
    [
        #  PA    NA    BR    VIO    JS
        # Latent values boosted to compensate for Likert discretization attenuation
        # (observed/latent factor ~0.65-0.78 for skewed intake scales).
        # Attenuation is strongest on PA (top-loaded) and NA (bottom-loaded).
        [1.00, -0.58, -0.38, -0.32, 0.58],  # PA
        [-0.58, 1.00, 0.52, 0.46, -0.52],  # NA
        [-0.38, 0.52, 1.00, 0.88, -0.60],  # BR
        [-0.32, 0.46, 0.88, 1.00, -0.52],  # VIO
        [0.58, -0.52, -0.60, -0.52, 1.00],  # JS
    ]
)

# --- L1 ICC values ---
# Ordering: PF, CW, EE, NF_COMP, NF_AUTO, NF_RELT, TI, ATCB, MTG_N, MTG_T
#
# Literature:
#   burnout (SMBM) ICCs: .40-.55  Sonnentag (2018); Vahle-Hinz et al. (2021)
#   NF (PNTS) ICCs:      .35-.50  Schuler et al. (2019)
#   TI ICC:              .50-.65  attitudes are stable; Riketta & Van Dick (2005)
#   ATCB (marker):       .30      near-zero true stability; Lindell & Whitney (2001)
#   meetings:            .55-.65  relatively stable daily pattern
#
# All at or slightly above the power-analysis medium ICC scenario (.30-.50).

L1_ICC = np.array([0.45, 0.45, 0.40, 0.40, 0.40, 0.35, 0.50, 0.30, 0.60, 0.60])

# --- L1 between-person correlation matrix ---
# BP: trait-level, stronger associations.
# Ordering: PF(0), CW(1), EE(2), NF_COMP(3), NF_AUTO(4), NF_RELT(5),
#           TI(6), ATCB(7), MTG_N(8), MTG_T(9)

L1_BP_CORR = np.array(
    [
        #  PF    CW    EE   NFC   NFA   NFR    TI   ATCB  MTGN  MTGT
        # Burnout facets boosted to .75-.80 (latent) to produce observed .55-.65.
        # NF facets boosted to .70-.76 to produce observed .50-.60.
        [1.00, 0.78, 0.75, 0.50, 0.50, 0.45, 0.50, 0.05, 0.15, 0.15],  # PF
        [0.78, 1.00, 0.78, 0.50, 0.50, 0.45, 0.50, 0.05, 0.15, 0.15],  # CW
        [0.75, 0.78, 1.00, 0.45, 0.45, 0.40, 0.45, 0.05, 0.12, 0.12],  # EE
        [0.50, 0.50, 0.45, 1.00, 0.76, 0.70, 0.40, 0.05, 0.15, 0.15],  # NF_COMP
        [0.50, 0.50, 0.45, 0.76, 1.00, 0.76, 0.40, 0.05, 0.15, 0.15],  # NF_AUTO
        [0.45, 0.45, 0.40, 0.70, 0.76, 1.00, 0.40, 0.05, 0.12, 0.12],  # NF_RELT
        [0.50, 0.50, 0.45, 0.40, 0.40, 0.40, 1.00, 0.05, 0.20, 0.20],  # TI
        [0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 1.00, 0.00, 0.00],  # ATCB
        [0.15, 0.15, 0.12, 0.15, 0.15, 0.12, 0.20, 0.00, 1.00, 0.85],  # MTG_N
        [0.15, 0.15, 0.12, 0.15, 0.15, 0.12, 0.20, 0.00, 0.85, 1.00],  # MTG_T
    ]
)

# --- L1 within-person correlation matrix ---
# WP: state-level occasion-specific fluctuations, weaker than BP.
#
# Key within-person effects (H1a, H1b, H4a, H4b):
#   r(NF_COMP_WP, PF_WP)  ~ .40  need frustration drives physical fatigue within-day
#   r(NF_COMP_WP, TI_WP)  ~ .25  H1b: medium-small WP effect per facet (composite ~.30)
#   r(PF_WP,      TI_WP)  ~ .30  H1a: medium WP effect per facet (composite ~.35)
#   r(MTG_N_WP, NF_WP)    ~ .18  H4: meetings elevate momentary need frustration
#   r(MTG_N_WP, TI_WP)    ~ .15  direct meeting -> TI path within-person
#   ATCB_WP near-zero with study variables (CMB marker)

L1_WP_CORR = np.array(
    [
        #  PF    CW    EE   NFC   NFA   NFR    TI   ATCB  MTGN  MTGT
        # Burnout facets boosted to .70-.72 (latent) to produce observed .55-.62.
        # NF facets boosted to .65-.70 to produce observed .50-.57.
        [1.00, 0.70, 0.65, 0.40, 0.40, 0.35, 0.30, 0.02, 0.15, 0.15],  # PF
        [0.70, 1.00, 0.72, 0.40, 0.40, 0.35, 0.30, 0.02, 0.15, 0.15],  # CW
        [0.65, 0.72, 1.00, 0.35, 0.35, 0.30, 0.28, 0.02, 0.12, 0.12],  # EE
        [0.40, 0.40, 0.35, 1.00, 0.68, 0.63, 0.25, 0.02, 0.18, 0.18],  # NF_COMP
        [0.40, 0.40, 0.35, 0.68, 1.00, 0.68, 0.25, 0.02, 0.18, 0.18],  # NF_AUTO
        [0.35, 0.35, 0.30, 0.63, 0.68, 1.00, 0.22, 0.02, 0.15, 0.15],  # NF_RELT
        [0.30, 0.30, 0.28, 0.25, 0.25, 0.22, 1.00, 0.02, 0.15, 0.15],  # TI
        [0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 1.00, 0.00, 0.00],  # ATCB
        [0.15, 0.15, 0.12, 0.18, 0.18, 0.15, 0.15, 0.00, 1.00, 0.80],  # MTG_N
        [0.15, 0.15, 0.12, 0.18, 0.18, 0.15, 0.15, 0.00, 0.80, 1.00],  # MTG_T
    ]
)

# =============================================================================
# [5] SIMULATION HELPERS
# =============================================================================


def nearest_psd(matrix: np.ndarray) -> np.ndarray:
    """Project matrix to nearest positive semi-definite via eigenvalue clipping."""
    eigenvalues, eigenvectors = np.linalg.eigh(matrix)
    eigenvalues = np.maximum(eigenvalues, 1e-8)
    return eigenvectors @ np.diag(eigenvalues) @ eigenvectors.T


def mvn_cholesky(n: int, corr: np.ndarray) -> np.ndarray:
    """
    Draw n samples from MVN(0, corr) using Cholesky decomposition.

    Returns array of shape (n, k) where k = corr.shape[0].
    Falls back to nearest-PSD projection if the matrix is not positive definite.
    """
    try:
        L = np.linalg.cholesky(corr)
    except np.linalg.LinAlgError:
        L = np.linalg.cholesky(nearest_psd(corr))
    z = RNG.standard_normal((n, corr.shape[0]))
    return z @ L.T


def continuous_to_likert(
    scores: np.ndarray,
    thresholds: list[float],
    labels: list[str],
) -> list[str]:
    """
    Map a continuous array to Likert string labels using breakpoints on the
    standard normal scale.

    Parameters
    ----------
    scores     : 1-D array of continuous values (assumed approximately N(0,1))
    thresholds : len(labels) - 1 sorted breakpoints
    labels     : ordered label strings; labels[0] corresponds to the lowest scores
    """
    result: list[str] = []
    for s in scores:
        assigned = False
        for i, t in enumerate(thresholds):
            if s <= t:
                result.append(labels[i])
                assigned = True
                break
        if not assigned:
            result.append(labels[-1])
    return result


def item_from_construct(construct: np.ndarray, loading: float) -> np.ndarray:
    """
    Generate a single item from a latent construct with a given factor loading.
    item = loading * construct + sqrt(1 - loading^2) * unique_noise
    """
    unique = RNG.standard_normal(len(construct))
    return loading * construct + np.sqrt(1.0 - loading**2) * unique


# =============================================================================
# [6] INTAKE (L2) DATA GENERATION
# =============================================================================


def generate_intake_scales(intake_meta: pd.DataFrame) -> pd.DataFrame:
    """
    Generate L2 scale items (PA, NA, BR, VIO, JS) for the intake survey.
    All non-scale metadata columns are preserved from intake_meta.

    Returns a DataFrame with the same columns as intake_meta plus scale columns
    in their original positions.
    """
    n = len(intake_meta)

    # Latent L2 constructs from multivariate normal
    # Ordering: PA(0), NA(1), BR(2), VIO(3), JS(4)
    latent = mvn_cholesky(n, L2_CORR)

    lat_pa = latent[:, 0]
    lat_na = latent[:, 1]
    lat_br = latent[:, 2]
    lat_vio = latent[:, 3]
    lat_js = latent[:, 4]

    df = intake_meta.copy()

    # PA items — intake frequency scale
    for i, lam in enumerate(LOADINGS["pa"], start=1):
        item = item_from_construct(lat_pa, lam)
        df[f"pa{i}"] = continuous_to_likert(item, THRESH_PA, INTAKE_FREQ)

    # NA items — intake frequency scale
    for i, lam in enumerate(LOADINGS["na"], start=1):
        item = item_from_construct(lat_na, lam)
        df[f"na{i}"] = continuous_to_likert(item, THRESH_NA_INTAKE, INTAKE_FREQ)

    # PC Breach items — agreement scale
    for i, lam in enumerate(LOADINGS["br"], start=1):
        item = item_from_construct(lat_br, lam)
        df[f"br{i}"] = continuous_to_likert(item, THRESH_BR, AGREE)

    # PC Violation items — agreement scale
    for i, lam in enumerate(LOADINGS["vio"], start=1):
        item = item_from_construct(lat_vio, lam)
        df[f"vio{i}"] = continuous_to_likert(item, THRESH_VIO, AGREE)

    # Job Satisfaction — single item, agreement scale
    # No loading noise for a single item; use raw latent score
    df["js1"] = continuous_to_likert(lat_js, THRESH_JS, AGREE)

    return df


# =============================================================================
# [7] FOLLOWUP (L1) DATA GENERATION
# =============================================================================


def generate_followup_scales(followup_meta: pd.DataFrame) -> pd.DataFrame:
    """
    Generate L1 scale items using a multilevel simulation.

    Each construct is decomposed into:
        score_jt = sqrt(ICC) * BP_j + sqrt(1 - ICC) * WP_jt

    BP_j:   person-level random effect — constant across all timepoints for person j
    WP_jt:  occasion-specific residual — independent across persons and timepoints

    L1 construct ordering (10 total):
        PF(0), CW(1), EE(2), NF_COMP(3), NF_AUTO(4), NF_RELT(5),
        TI(6), ATCB(7), MTG_N(8), MTG_T(9)
    """
    participants = followup_meta["response_id"].unique()
    n_persons = len(participants)
    n_obs = len(followup_meta)

    assert n_persons == N_PARTICIPANTS, (
        f"Expected {N_PARTICIPANTS} unique participants; got {n_persons}"
    )

    # --- Between-person components: one vector per participant ---
    bp = mvn_cholesky(n_persons, L1_BP_CORR)  # (n_persons, 10)
    bp_map = {pid: bp[i] for i, pid in enumerate(participants)}

    # --- Within-person residuals: one vector per observation ---
    wp = mvn_cholesky(n_obs, L1_WP_CORR)  # (n_obs, 10)

    # --- Align BP to observation rows ---
    bp_aligned = np.array(
        [bp_map[pid] for pid in followup_meta["response_id"]]
    )  # (n_obs, 10)

    # --- Combine: total = sqrt(ICC) * BP + sqrt(1-ICC) * WP ---
    total = bp_aligned * np.sqrt(L1_ICC) + wp * np.sqrt(
        1.0 - L1_ICC
    )  # (n_obs, 10)

    lat_pf = total[:, 0]
    lat_cw = total[:, 1]
    lat_ee = total[:, 2]
    lat_nf_comp = total[:, 3]
    lat_nf_auto = total[:, 4]
    lat_nf_relt = total[:, 5]
    lat_ti = total[:, 6]
    lat_atcb = total[:, 7]
    lat_mtg_n = total[:, 8]
    lat_mtg_t = total[:, 9]

    df = followup_meta.copy()

    # --- SMBM: Physical Fatigue (pf1-pf6) ---
    for i, lam in enumerate(LOADINGS["pf"], start=1):
        item = item_from_construct(lat_pf, lam)
        df[f"pf{i}"] = continuous_to_likert(item, THRESH_PF, FOLLOWUP_FREQ)

    # --- SMBM: Cognitive Weariness (cw1-cw5) ---
    for i, lam in enumerate(LOADINGS["cw"], start=1):
        item = item_from_construct(lat_cw, lam)
        df[f"cw{i}"] = continuous_to_likert(item, THRESH_CW, FOLLOWUP_FREQ)

    # --- SMBM: Emotional Exhaustion (ee1-ee3) ---
    for i, lam in enumerate(LOADINGS["ee"], start=1):
        item = item_from_construct(lat_ee, lam)
        df[f"ee{i}"] = continuous_to_likert(item, THRESH_EE, FOLLOWUP_FREQ)

    # --- PNTS: Competence thwarting (comp1-comp4) ---
    for i, lam in enumerate(LOADINGS["comp"], start=1):
        item = item_from_construct(lat_nf_comp, lam)
        df[f"comp{i}"] = continuous_to_likert(item, THRESH_NF_COMP, AGREE)

    # --- PNTS: Autonomy thwarting (auto1-auto4) ---
    for i, lam in enumerate(LOADINGS["auto"], start=1):
        item = item_from_construct(lat_nf_auto, lam)
        df[f"auto{i}"] = continuous_to_likert(item, THRESH_NF_AUTO, AGREE)

    # --- PNTS: Relatedness thwarting (relt1-relt4) ---
    for i, lam in enumerate(LOADINGS["relt"], start=1):
        item = item_from_construct(lat_nf_relt, lam)
        df[f"relt{i}"] = continuous_to_likert(item, THRESH_NF_RELT, AGREE)

    # --- ATCB marker variable (atcb2, atcb5, atcb6, atcb7) ---
    for col, lam in zip(["atcb2", "atcb5", "atcb6", "atcb7"], LOADINGS["atcb"]):
        item = item_from_construct(lat_atcb, lam)
        df[col] = continuous_to_likert(item, THRESH_ATCB, AGREE)

    # --- Turnover intention (single item, SMBM frequency anchors) ---
    df["turnover_intention"] = continuous_to_likert(
        lat_ti, THRESH_TI, FOLLOWUP_FREQ
    )

    # --- Meeting count: map latent score to integers [0, 8] ---
    # lat_mtg_n is approx N(0,1); map to Poisson-like distribution centered at 2.5
    mtg_count = np.clip(np.round(2.5 + 1.5 * lat_mtg_n).astype(int), 0, 8)
    df["meetings_num"] = mtg_count

    # --- Meeting minutes: conditional on count; per-meeting duration ~35 min ---
    # lat_mtg_t adds between-occasion variability in duration per meeting.
    # Clamp per-meeting duration to [1, 240] so extreme lat_mtg_t values never
    # produce a negative product that clips to zero for positive mtg_count.
    per_meeting_duration = np.clip(35.0 + 12.0 * lat_mtg_t, 1.0, 240.0)
    mtg_time_raw = mtg_count * per_meeting_duration
    mtg_time = np.where(
        mtg_count == 0, 0, np.clip(np.round(mtg_time_raw).astype(int), 1, 240)
    )
    df["meetings_time"] = mtg_time.astype(int)

    return df


# =============================================================================
# [8] BIGQUERY STAGING LOAD
# =============================================================================


def load_to_bigquery(
    intake_path: Path,
    followup_path: Path,
    project: str = BQ_PROJECT,
    dataset: str = BQ_DATASET,
) -> None:
    """
    Load updated CSVs into BigQuery staging tables using the production table
    schema.  Replaces syn_intake_responses_infra.sh and
    syn_followup_responses_infra.sh.

    Schema is cloned from production qualtrics.* tables (identical to the
    original shell scripts).  Idempotent: truncates before loading.
    """
    try:
        from google.api_core.exceptions import NotFound
        from google.cloud import bigquery
    except ImportError:
        sys.exit(
            "ERROR: google-cloud-bigquery is not installed. "
            "Run: poetry install --with fn-qualtrics-scheduling"
        )

    client = bigquery.Client(project=project)

    for table_name, csv_path in [
        ("stg_intake_responses", intake_path),
        ("stg_followup_responses", followup_path),
    ]:
        qualified = f"{project}.{dataset}.{table_name}"
        source = f"{project}.qualtrics.{table_name}"

        print(f"  Loading {csv_path.name} -> {qualified} ...", flush=True)

        # 1. Ensure dataset exists
        ds_ref = f"{project}.{dataset}"
        try:
            client.get_dataset(ds_ref)
        except NotFound:
            ds = bigquery.Dataset(ds_ref)
            ds.location = "US"
            client.create_dataset(ds, exists_ok=True)
            print(f"    Created dataset {dataset}")

        # 2. Clone schema from production, create table if it doesn't exist
        client.query(
            f"CREATE TABLE IF NOT EXISTS `{qualified}` LIKE `{source}`;"
        ).result()

        # 3. Truncate for idempotency
        client.query(f"TRUNCATE TABLE `{qualified}`;").result()

        # 4. Load CSV using production schema
        source_table = client.get_table(source)
        job_config = bigquery.LoadJobConfig(
            source_format=bigquery.SourceFormat.CSV,
            skip_leading_rows=1,
            schema=source_table.schema,
            write_disposition="WRITE_TRUNCATE",
        )
        with open(csv_path, "rb") as f:
            job = client.load_table_from_file(
                f, qualified, job_config=job_config
            )
            job.result()

        # 5. Verify
        table = client.get_table(qualified)
        print(f"    Rows: {table.num_rows}  Columns: {len(table.schema)}")


# =============================================================================
# [9] ENTRY POINT
# =============================================================================


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate psychologically calibrated synthetic ESM data."
    )
    parser.add_argument(
        "--load-bq",
        action="store_true",
        help="Load updated CSVs into BigQuery staging tables (requires gcloud auth).",
    )
    args = parser.parse_args()

    print(f"Reading existing CSVs from {IMPORT_DIR}")
    intake_raw = pd.read_csv(INTAKE_CSV)
    followup_raw = pd.read_csv(FOLLOWUP_CSV)
    print(
        f"  Intake:   {len(intake_raw):>4} rows, {len(intake_raw.columns)} columns"
    )
    print(
        f"  Followup: {len(followup_raw):>4} rows, {len(followup_raw.columns)} columns"
    )

    # Columns that are regenerated (everything else is metadata and passes through)
    intake_scale_cols = (
        [f"pa{i}" for i in range(1, 6)]
        + [f"na{i}" for i in range(1, 6)]
        + [f"br{i}" for i in range(1, 6)]
        + [f"vio{i}" for i in range(1, 5)]
        + ["js1"]
    )
    followup_scale_cols = (
        [f"pf{i}" for i in range(1, 7)]
        + [f"cw{i}" for i in range(1, 6)]
        + [f"ee{i}" for i in range(1, 4)]
        + [f"comp{i}" for i in range(1, 5)]
        + [f"auto{i}" for i in range(1, 5)]
        + [f"relt{i}" for i in range(1, 5)]
        + ["atcb2", "atcb5", "atcb6", "atcb7"]
        + ["turnover_intention", "meetings_num", "meetings_time"]
    )

    intake_meta_cols = [
        c for c in intake_raw.columns if c not in intake_scale_cols
    ]
    followup_meta_cols = [
        c for c in followup_raw.columns if c not in followup_scale_cols
    ]

    print("\nGenerating intake scale items (L2 MVN simulation)...")
    intake_new = generate_intake_scales(intake_raw[intake_meta_cols])
    intake_new = intake_new[intake_raw.columns]  # restore original column order

    print("Generating followup scale items (L1 multilevel simulation)...")
    followup_new = generate_followup_scales(followup_raw[followup_meta_cols])
    followup_new = followup_new[
        followup_raw.columns
    ]  # restore original column order

    print(f"\nWriting {INTAKE_CSV.name} ...")
    intake_new.to_csv(INTAKE_CSV, index=False)

    print(f"Writing {FOLLOWUP_CSV.name} ...")
    followup_new.to_csv(FOLLOWUP_CSV, index=False)

    print("Done.")

    if args.load_bq:
        print("\nLoading to BigQuery staging tables...")
        load_to_bigquery(INTAKE_CSV, FOLLOWUP_CSV)
        print("BigQuery staging tables updated.")
        print(
            "\nNext: run the int_*.sql and fct_*.sql pipeline, then"
            " export_syn_fct_panel_responses_csv.sh to regenerate the R-ready CSV."
        )
    else:
        print(
            "\nTo load into BigQuery, rerun with --load-bq, then run the int_*.sql"
            " and fct_*.sql pipeline."
        )


if __name__ == "__main__":
    main()
