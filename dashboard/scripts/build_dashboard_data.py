"""
Build dashboard/data/dashboard.json from frozen analysis outputs.

Data frozen: 2026-06-12 submission snapshot.
Run: uv run dashboard/scripts/build_dashboard_data.py

All source CSVs are under analysis/run_study_analysis/figs/.
No external dependencies beyond Python stdlib.
"""

import csv
import json
from pathlib import Path

REPO = Path(__file__).parent.parent.parent
FIGS = REPO / "analysis" / "run_study_analysis" / "figs"
OUT = REPO / "dashboard" / "data" / "dashboard.json"

FREEZE_DATE = "2026-06-12"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def na_float(v):
    """Convert NA-as-string to None; otherwise return float."""
    if v is None or str(v).strip().upper() == "NA" or str(v).strip() == "":
        return None
    return float(v)


def na_str(v):
    """Convert NA-as-string to None; otherwise return stripped string."""
    if v is None or str(v).strip().upper() == "NA" or str(v).strip() == "":
        return None
    return str(v).strip()


def read_csv(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def parse_pct_str(s):
    """Parse '4.5%' -> 4.5."""
    return float(s.strip().rstrip("%"))


# Plain-language variable labels used across sections
VAR_LABELS = {
    # Within-person (L1) burnout / NF / outcomes
    "pf_mean": "Physical Fatigue",
    "pf_mean_within": "Physical Fatigue (within)",
    "pf_mean_between": "Physical Fatigue (between)",
    "cw_mean": "Cognitive Weariness",
    "cw_mean_within": "Cognitive Weariness (within)",
    "cw_mean_between": "Cognitive Weariness (between)",
    "ee_mean": "Emotional Exhaustion",
    "ee_mean_within": "Emotional Exhaustion (within)",
    "ee_mean_between": "Emotional Exhaustion (between)",
    "comp_mean": "Competence Frustration",
    "comp_mean_within": "Competence Frustration (within)",
    "comp_mean_between": "Competence Frustration (between)",
    "auto_mean": "Autonomy Frustration",
    "auto_mean_within": "Autonomy Frustration (within)",
    "auto_mean_between": "Autonomy Frustration (between)",
    "relt_mean": "Relatedness Frustration",
    "relt_mean_within": "Relatedness Frustration (within)",
    "relt_mean_between": "Relatedness Frustration (between)",
    "atcb_mean": "Turnover Cognitions",
    "atcb_mean_within": "Turnover Cognitions (within)",
    "turnover_intention_mean": "Turnover Intentions",
    "nf_mean_within": "Need Frustration composite (within)",
    "nf_mean_between": "Need Frustration composite (between)",
    "burnout_mean_within": "Burnout composite (within)",
    "burnout_mean_between": "Burnout composite (between)",
    # M7a / M7b interaction terms
    "nf_mean_within:meetings_count_within": "Need Frustration x Meeting Count",
    "nf_mean_within:meetings_time_within": "Need Frustration x Meeting Duration",
    "burnout_mean_within:meetings_count_within": "Burnout x Meeting Count",
    "burnout_mean_within:meetings_time_within": "Burnout x Meeting Duration",
    # Between-person (L2)
    "pa_mean": "Positive Affect",
    "pa_mean_c": "Positive Affect (mean-centered)",
    "na_mean": "Negative Affect",
    "na_mean_c": "Negative Affect (mean-centered)",
    "br_mean": "Psychological Contract Breach",
    "br_mean_c": "PC Breach (mean-centered)",
    "vio_mean": "Psychological Contract Violation",
    "vio_mean_c": "PC Violation (mean-centered)",
    "js_mean": "Job Satisfaction",
    "js_mean_c": "Job Satisfaction (mean-centered)",
    "jis_mean": "Job Insecurity",
    "jis_mean_c": "Job Insecurity (mean-centered)",
    "des_mean": "Distributive Equity Sensitivity",
    "des_mean_c": "Equity Sensitivity (mean-centered)",
    "age": "Age",
    "age_c": "Age (mean-centered)",
    # Time
    "timepoint": "Time of Day",
    "time_c": "Time (centered)",
    "meetings_count": "Meeting Count",
    "meetings_count_within": "Meeting Count (within)",
    "meetings_count_between": "Meeting Count (between)",
    "meetings_time": "Meeting Duration",
    "meetings_time_within": "Meeting Duration (within)",
    "meetings_time_between": "Meeting Duration (between)",
    # Intercept
    "(Intercept)": "Intercept",
    # Covariates
    "work_hours_c": "Work Hours",
    "remote_worker": "Remote Worker",
    "work_classification": "Work Shift",
    "recruitment_sourcesnowball": "Recruitment: Snowball",
    "job_tenureLess than a year": "Job Tenure: < 1 yr",
    "job_tenure3 to 5 years": "Job Tenure: 3-5 yrs",
    "job_tenureMore than 5 years": "Job Tenure: > 5 yrs",
}


# ---------------------------------------------------------------------------
# Section builders
# ---------------------------------------------------------------------------


def build_meta():
    return {
        "study_title": "Within-Person Fluctuation in Burnout, Need Frustration, and Turnover Intentions",
        "freeze_date": FREEZE_DATE,
        "n_participants": 336,
        "n_observations": 1008,
        "design": "3-wave ESM (9AM, 1PM, 5PM), N=336 knowledge workers",
        "source": "analysis/run_study_analysis/figs/ (frozen 2026-06-12)",
    }


def build_funnel():
    # Source: METHOD_NOTES -- 623 intake -> 351 complete -> 336 analytic
    return {
        "steps": [
            {"label": "Intake surveys started", "n": 623},
            {"label": "Completed intake survey", "n": 351},
            {"label": "Entered ESM phase", "n": 351},
            {"label": "Analytic sample", "n": 336},
        ],
        "excluded": 15,
        "exclusion_reason": "Did not complete ESM phase or failed data quality checks",
        "n_observations": 1008,
        "source": "METHOD_NOTES (submission freeze 2026-06-12)",
    }


def build_sample():
    categorical_rows = read_csv(FIGS / "eda" / "eda_10_table1_categorical.csv")
    continuous_rows = read_csv(FIGS / "eda" / "eda_10_table1_continuous.csv")

    categorical = [
        {
            "variable": r["variable"],
            "level": r["level"],
            "n": int(r["n"]),
            "pct_str": r["pct"],
            "pct": parse_pct_str(r["pct"]),
        }
        for r in categorical_rows
    ]

    continuous = [
        {
            "variable": r["variable"],
            "label": VAR_LABELS.get(r["variable"], r["variable"]),
            "n": int(r["n"]),
            "mean": float(r["mean"]),
            "sd": float(r["sd"]),
        }
        for r in continuous_rows
    ]

    return {
        "n": 336,
        "categorical": categorical,
        "continuous": continuous,
        "source": "eda_10_table1_categorical.csv, eda_10_table1_continuous.csv",
    }


def build_correlations():
    def parse_matrix(matrix_path, pvalue_path):
        mat_rows = read_csv(matrix_path)
        pval_rows = read_csv(pvalue_path)

        # Both CSVs have an empty-string first column (raw CSV header); use it as the row label
        label_col = next(iter(mat_rows[0]))
        pval_label_col = next(iter(pval_rows[0]))

        # variable names = all columns except the label column
        variables = [c for c in mat_rows[0].keys() if c != label_col]

        # index p-value rows by row label
        pval_index = {r[pval_label_col]: r for r in pval_rows}

        pairs = []

        for i, r in enumerate(mat_rows):
            row_var = r[label_col]
            pval_row = pval_index.get(row_var, {})
            for j, col_var in enumerate(variables):
                if j >= i:
                    continue  # lower triangle only (no diagonal)
                r_val = na_float(r.get(col_var))
                p_val = na_float(pval_row.get(col_var))
                pairs.append(
                    {
                        "row": row_var,
                        "col": col_var,
                        "row_label": VAR_LABELS.get(row_var, row_var),
                        "col_label": VAR_LABELS.get(col_var, col_var),
                        "r": round(r_val, 4) if r_val is not None else None,
                        "p": p_val,
                        "sig": p_val is not None and p_val < 0.05,
                    }
                )

        var_meta = [
            {"key": v, "label": VAR_LABELS.get(v, v)} for v in variables
        ]
        return {"variables": var_meta, "pairs": pairs}

    within = parse_matrix(
        FIGS / "corr" / "corr_04_rmcorr_within_matrix.csv",
        FIGS / "corr" / "corr_04_rmcorr_within_pvalues.csv",
    )
    between = parse_matrix(
        FIGS / "corr" / "corr_01_l2_pearson_matrix.csv",
        FIGS / "corr" / "corr_01_l2_pearson_pvalues.csv",
    )

    return {
        "within": {
            **within,
            "method": "rmcorr (within-person repeated-measures correlation)",
        },
        "between": {
            **between,
            "method": "Pearson (between-person, aggregated means)",
        },
        "source": "corr_04_rmcorr_within_matrix.csv, corr_01_l2_pearson_matrix.csv",
    }


def build_variance():
    rows = read_csv(FIGS / "eda" / "eda_15_icc_table.csv")
    var_labels = {
        "pf_mean": "Physical Fatigue",
        "cw_mean": "Cognitive Weariness",
        "ee_mean": "Emotional Exhaustion",
        "comp_mean": "Competence Frustration",
        "auto_mean": "Autonomy Frustration",
        "relt_mean": "Relatedness Frustration",
        "atcb_mean": "Turnover Cognitions (ATCB)",
        "turnover_intention_mean": "Turnover Intentions",
    }
    variables = [
        {
            "variable": r["variable"],
            "label": var_labels.get(r["variable"], r["variable"]),
            "icc": round(float(r["icc_adjusted"]), 4),
            "var_between": round(float(r["var_between"]), 4),
            "var_within": round(float(r["var_within"]), 4),
            "var_total": round(float(r["var_total"]), 4),
            "pct_between": round(float(r["pct_between"]) * 100, 1),
            "pct_within": round(float(r["pct_within"]) * 100, 1),
        }
        for r in rows
    ]

    # Locate TI row for the headline anchor value
    ti_row = next(
        v for v in variables if v["variable"] == "turnover_intention_mean"
    )

    return {
        "icc_ti": round(ti_row["icc"], 4),
        "pct_between_ti": ti_row["pct_between"],
        "pct_within_ti": ti_row["pct_within"],
        "variables": variables,
        "source": "eda_15_icc_table.csv",
    }


def build_models():
    comp_rows = read_csv(FIGS / "mlm" / "mlm_01_model_comparison.csv")
    fx_rows = read_csv(FIGS / "mlm" / "mlm_02_fixed_effects.csv")

    comparison = []
    for r in comp_rows:
        comparison.append(
            {
                "model": r["Model"],
                "aic": round(float(r["AIC"]), 2),
                "bic": round(float(r["BIC"]), 2),
                "log_lik": round(float(r["logLik"]), 4),
                "n_fixed": int(r["n_fixed"]),
                "r2_marginal": round(float(r["R2_marginal"]), 4),
                "r2_conditional": round(float(r["R2_conditional"]), 4),
                "tau_00": round(float(r["tau_00"]), 4),
                "tau_11": na_float(r["tau_11"]),
                "sigma2": round(float(r["sigma2"]), 4),
                "lrt_chi2": na_float(r["LRT_chi2"]),
                "lrt_df": na_float(r["LRT_df"]),
                "lrt_p": na_float(r["LRT_p"]),
            }
        )

    # Group fixed effects by model
    fixed_effects = {}
    for r in fx_rows:
        if r["effect"] != "fixed":
            continue
        model = r["model"]
        if model not in fixed_effects:
            fixed_effects[model] = []
        fixed_effects[model].append(
            {
                "term": r["term"],
                "label": VAR_LABELS.get(r["term"], r["term"]),
                "estimate": round(float(r["estimate"]), 4),
                "std_error": round(float(r["std.error"]), 4),
                "statistic": round(float(r["statistic"]), 3),
                "df": round(float(r["df"]), 1),
                "p_value": float(r["p.value"]),
                "conf_low": round(float(r["conf.low"]), 4),
                "conf_high": round(float(r["conf.high"]), 4),
            }
        )

    return {
        "comparison": comparison,
        "fixed_effects": fixed_effects,
        "source": "mlm_01_model_comparison.csv, mlm_02_fixed_effects.csv",
    }


def build_effects():
    std_rows = read_csv(FIGS / "mlm" / "mlm_05_standardized_effects.csv")
    es_rows = read_csv(FIGS / "mlm" / "mlm_06_level_specific_es.csv")
    dr2_rows = read_csv(FIGS / "mlm" / "mlm_07_delta_r2.csv")
    iccb_rows = read_csv(FIGS / "mlm" / "mlm_08_iccbeta.csv")

    # Standardized coefficients (beta) grouped by model; used in Model Explorer tooltip.
    # Field renamed "term" (was "parameter") for JS consistency.
    standardized = {}
    for r in std_rows:
        if r["Parameter"] == "(Intercept)":
            continue
        model = r["model"]
        if model not in standardized:
            standardized[model] = []
        standardized[model].append(
            {
                "term": r["Parameter"],
                "label": VAR_LABELS.get(r["Parameter"], r["Parameter"]),
                "std_coef": round(float(r["Std_Coefficient"]), 4),
                "ci_low": round(float(r["CI_low"]), 4),
                "ci_high": round(float(r["CI_high"]), 4),
            }
        )

    # Level-specific pseudo-d effect sizes; used for the forest plot.
    # pseudo_d is a Cohen's d-like metric rescaled to the DV SD at each level.
    level_specific = {}
    for r in es_rows:
        model = r["model"]
        if model not in level_specific:
            level_specific[model] = []
        level_specific[model].append(
            {
                "term": r["term"],
                "label": VAR_LABELS.get(r["term"], r["term"]),
                "level": r["level"],
                "pseudo_d": round(float(r["pseudo_d"]), 4),
                "pseudo_d_lo": round(float(r["pseudo_d_lo"]), 4),
                "pseudo_d_hi": round(float(r["pseudo_d_hi"]), 4),
                "magnitude": r["magnitude"],
            }
        )

    delta_r2 = [
        {
            "model": r["Model"],
            "r2_marginal": round(float(r["R2_marginal"]), 4),
            "r2_conditional": round(float(r["R2_conditional"]), 4),
            "delta_r2_marginal": round(float(r["delta_R2_marginal"]), 4),
            "delta_r2_conditional": round(float(r["delta_R2_conditional"]), 4),
            "f2": round(float(r["f2"]), 4),
            "f2_magnitude": r["f2_magnitude"],
        }
        for r in dr2_rows
    ]

    iccbeta = [
        {
            "predictor": r["predictor"],
            "label": VAR_LABELS.get(r["predictor"], r["predictor"]),
            "rho_beta": round(float(r["rho_beta"]), 4),
            "tau11": round(float(r["tau11"]), 4),
            "model_status": r["model_status"],
            "magnitude": r["magnitude"],
        }
        for r in iccb_rows
    ]

    return {
        "standardized": standardized,
        "level_specific": level_specific,
        "delta_r2": delta_r2,
        "iccbeta": iccbeta,
        "source": "mlm_05_standardized_effects.csv, mlm_06_level_specific_es.csv, mlm_07_delta_r2.csv, mlm_08_iccbeta.csv",
    }


def build_hypotheses():
    rows = read_csv(FIGS / "mlm" / "mlm_04_hypothesis_tests.csv")

    # Plain-language hypothesis descriptions for general audience
    plain_descriptions = {
        "H1a:comp": "When competence need frustration rises within a day, turnover thoughts increase",
        "H1a:auto": "When autonomy need frustration rises within a day, turnover thoughts increase",
        "H1a:relt": "When relatedness need frustration rises within a day, turnover thoughts increase",
        "H1b:comp": "Employees with chronically higher competence frustration report more turnover thoughts",
        "H1b:auto": "Employees with chronically higher autonomy frustration report more turnover thoughts",
        "H1b:relt": "Employees with chronically higher relatedness frustration report more turnover thoughts",
        "H2a:pf": "When physical fatigue rises within a day, turnover thoughts increase",
        "H2a:cw": "When cognitive weariness rises within a day, turnover thoughts increase",
        "H2a:ee": "When emotional exhaustion rises within a day, turnover thoughts increase",
        "H2b:pf": "Employees with chronically higher physical fatigue report more turnover thoughts",
        "H2b:cw": "Employees with chronically higher cognitive weariness report more turnover thoughts",
        "H2b:ee": "Employees with chronically higher emotional exhaustion report more turnover thoughts",
        "H3a": "More meetings in a given timeblock amplify the effect of need frustration on turnover thoughts",
        "H3b": "More meetings in a given timeblock amplify the effect of burnout on turnover thoughts",
        "H4a": "Employees who perceive more contract breach report more turnover thoughts",
        "H4b": "Employees who feel more contract violation (emotional) report more turnover thoughts",
        "H5": "Employees who are more satisfied with their job report fewer turnover thoughts",
    }

    items = []
    for r in rows:
        hyp = r["hypothesis"]

        # Skip the structural prerequisite check (not a directional hypothesis)
        if hyp == "Prereq":
            continue

        # Collapse H3 sub-rows: keep only the "count" variant as the representative
        is_h3_time = hyp in ("H3a:time", "H3b:time")
        if is_h3_time:
            continue

        # Rename H3 count rows to their collapsed IDs
        display_id = hyp
        if hyp == "H3a:count":
            display_id = "H3a"
        elif hyp == "H3b:count":
            display_id = "H3b"

        # Parse h-number for ordering
        level = r["level"]
        supported = r["Supported"].strip().lower() in ("true", "yes")
        p_value = na_float(r["p_value"])
        estimate = na_float(r["Estimate"])

        items.append(
            {
                "id": display_id,
                "level": level,
                "level_short": "within" if "L1" in level else "between",
                "description": r["description"],
                "plain_description": plain_descriptions.get(
                    display_id, r["description"]
                ),
                "model_name": r["model_name"],
                "term": na_str(r["term"]),
                "direction": na_str(r["direction"]),
                "estimate": round(estimate, 4)
                if estimate is not None
                else None,
                "p_value": p_value,
                "supported": supported,
            }
        )

    supported_count = sum(1 for h in items if h["supported"])

    return {
        "total": len(items),
        "supported_count": supported_count,
        "items": items,
        "framing": f"{supported_count} of {len(items)} hypotheses supported",
        "source": "mlm_04_hypothesis_tests.csv",
    }


def build_measurement():
    fit_rows = read_csv(FIGS / "cfa" / "cfa_01_fit_indices.csv")
    omega_rows = read_csv(FIGS / "cfa" / "cfa_04_omega.csv")
    marker_ev_rows = read_csv(FIGS / "cfa" / "cfa_05_marker_evidence.csv")
    marker_fit_rows = read_csv(FIGS / "cfa" / "cfa_06_marker_fit.csv")
    marker_lrt_rows = read_csv(FIGS / "cfa" / "cfa_07_marker_lrt.csv")
    invariance_rows = read_csv(FIGS / "cfa" / "cfa_08_metric_invariance.csv")

    fit_indices = [
        {
            "model": r["model"],
            "chi_sq": round(float(r["chi_sq"]), 2),
            "df": int(r["df"]),
            "cfi": round(float(r["cfi"]), 3),
            "tli": round(float(r["tli"]), 3),
            "rmsea": round(float(r["rmsea"]), 3),
            "rmsea_lo": round(float(r["rmsea_lo"]), 3),
            "rmsea_hi": round(float(r["rmsea_hi"]), 3),
            "srmr": na_float(r["srmr"]),
            "srmr_within": na_float(r["srmr_within"]),
            "srmr_between": na_float(r["srmr_between"]),
        }
        for r in fit_rows
    ]

    omega = [
        {
            "level": r["level"],
            "factor": r["factor"],
            "omega": round(float(r["omega"]), 3),
            "type": r["type"],
        }
        for r in omega_rows
    ]

    # Marker variable: near-zero correlations with all L1 constructs
    marker_evidence = [
        {
            "variable": r["variable"],
            "label": VAR_LABELS.get(r["variable"], r["variable"]),
            "rmcorr_r": round(float(r["rmcorr_r"]), 4),
            "near_zero": r["near_zero"].strip().upper() == "TRUE",
        }
        for r in marker_ev_rows
    ]
    all_near_zero = all(e["near_zero"] for e in marker_evidence)

    # Marker model fit comparison
    marker_fit = [
        {
            "model": r["model"],
            "chi_sq": round(float(r["chi_sq"]), 2),
            "df": int(r["df"]),
            "cfi": round(float(r["cfi"]), 3),
            "rmsea": round(float(r["rmsea"]), 3),
            "srmr_within": na_float(r["srmr_within"]),
            "srmr_between": na_float(r["srmr_between"]),
            "delta_chisq": na_float(r["delta_chisq"]),
            "delta_df": na_float(r["delta_df"]),
            "p_diff": na_float(r["p_diff"]),
        }
        for r in marker_fit_rows
    ]

    # Marker LRT conclusions
    marker_lrt = [
        {
            "comparison": r["comparison"],
            "delta_chisq_sb": round(float(r["delta_chisq_sb"]), 3),
            "delta_df": int(r["delta_df"]),
            "p_value": round(float(r["p_value"]), 4),
            "conclusion": r["conclusion"],
        }
        for r in marker_lrt_rows
    ]
    # Key conclusion: Method-U vs. Method-R comparison must be non-significant
    _TARGET_COMPARISON = "Method-U vs. Method-R (fixed L1 factor covariances)"
    unbiased_lrt = next(
        (row for row in marker_lrt if row["comparison"] == _TARGET_COMPARISON),
        None,
    )
    unbiased = unbiased_lrt is not None and unbiased_lrt["p_value"] >= 0.05

    # Metric invariance
    metric_invariance = [
        {
            "model": r["model"],
            "chi2": round(float(r["chi2"]), 2),
            "df": int(r["df"]),
            "delta_chi2": na_float(r["delta_chi2"]),
            "delta_df": na_float(r["delta_df"]),
            "p_diff": na_float(r["p_diff"]),
            "result": na_str(r["result"]),
        }
        for r in invariance_rows
    ]
    _metric_row = next(
        (r for r in metric_invariance if r["model"].lower() == "metric"), None
    )
    invariance_supported = (
        _metric_row is not None
        and "supported" in (_metric_row["result"] or "").lower()
        and "not supported" not in (_metric_row["result"] or "").lower()
    )

    return {
        "fit_indices": fit_indices,
        "omega": omega,
        "marker_evidence": marker_evidence,
        "marker_all_near_zero": all_near_zero,
        "marker_fit": marker_fit,
        "marker_lrt": marker_lrt,
        "marker_unbiased": unbiased,
        "metric_invariance": metric_invariance,
        "metric_invariance_supported": invariance_supported,
        "source": (
            "cfa_01_fit_indices.csv, cfa_04_omega.csv, cfa_05_marker_evidence.csv, "
            "cfa_06_marker_fit.csv, cfa_07_marker_lrt.csv, cfa_08_metric_invariance.csv"
        ),
    }


# ---------------------------------------------------------------------------
# Anchor validation
# ---------------------------------------------------------------------------


def validate(data):
    errors = []

    if data["meta"]["n_participants"] != 336:
        errors.append(
            f"n_participants = {data['meta']['n_participants']}, expected 336"
        )

    if data["meta"]["n_observations"] != 1008:
        errors.append(
            f"n_observations = {data['meta']['n_observations']}, expected 1008"
        )

    icc = data["variance"]["icc_ti"]
    if abs(icc - 0.7923) > 0.001:
        errors.append(f"icc_ti = {icc}, expected ~0.7923")

    h_count = data["hypotheses"]["supported_count"]
    if h_count != 7:
        errors.append(f"supported_count = {h_count}, expected 7")

    h_total = data["hypotheses"]["total"]
    if h_total != 17:
        errors.append(f"hypotheses total = {h_total}, expected 17")

    n_models_comparison = len(data["models"]["comparison"])
    if n_models_comparison != 7:
        errors.append(
            f"model comparison rows = {n_models_comparison}, expected 7 (M0-M6)"
        )

    n_models_fx = len(data["models"]["fixed_effects"])
    if n_models_fx != 9:
        errors.append(f"fixed_effects models = {n_models_fx}, expected 9")

    if errors:
        print("VALIDATION ERRORS:")
        for e in errors:
            print(f"  - {e}")
        raise SystemExit(1)

    print("Validation passed:")
    print(
        f"  N = {data['meta']['n_participants']}, n_obs = {data['meta']['n_observations']}"
    )
    print(f"  ICC(TI) = {icc}")
    print(f"  Hypotheses: {h_count} of {h_total} supported")
    print(
        f"  Models: {n_models_comparison} in comparison table, {n_models_fx} with fixed effects"
    )


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main():
    print(f"Building dashboard.json from {FIGS}")
    print(f"Data freeze: {FREEZE_DATE}")

    data = {
        "meta": build_meta(),
        "funnel": build_funnel(),
        "sample": build_sample(),
        "correlations": build_correlations(),
        "variance": build_variance(),
        "models": build_models(),
        "effects": build_effects(),
        "hypotheses": build_hypotheses(),
        "measurement": build_measurement(),
    }

    validate(data)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=4)

    size_kb = OUT.stat().st_size / 1024
    print(f"Wrote {OUT} ({size_kb:.1f} KB)")


if __name__ == "__main__":
    main()
