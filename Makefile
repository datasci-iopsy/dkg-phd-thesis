# Project information
PROJECT_NAME := "If You Only Knew the Power of the Dark Side": Examining Within-Person \
  Fluctuation in Psychological Need Frustration, Burnout, and Turnover Intentions \
  Across a Workday
VERSION      := 1.0.0
AUTHOR       := Demetrius K. Green, ABD

# Absolute project root — prevents cd-induced relative path bugs
ROOT := $(CURDIR)

# R invocation — all R execution routed through uvr
RSCRIPT := uvr run

# Default GCP function; override: make gcp_dev FN=run-intake-confirmation
FN ?= run-qualtrics-scheduling

.DEFAULT_GOAL := help

# ---------------------------------------------------------------------------
# .PHONY declarations
# ---------------------------------------------------------------------------
.PHONY: help help_gcp welcome status clean \
        setup setup_r setup_python \
        validate \
        uvr_sync uvr_lock uvr_status uvr_doctor \
        power_analysis_dev power_analysis_prod \
        power_analysis_gcp_benchmark power_analysis_gcp_prod \
        power_analysis_gcp_posthoc \
        power_visual \
        synthetic_analysis synthetic_data_quality \
        synthetic_eda synthetic_measurement \
        synthetic_mlm synthetic_correlation synthetic_tables \
        study_export \
        study_analysis study_data_quality \
        study_eda study_measurement \
        study_mlm study_correlation study_tables \
        py_lint py_format py_sqlfmt py_test \
        gcp_dev gcp_deploy \
        gcp_infra_up gcp_infra_status gcp_infra_down \
        gcp_gateway_up gcp_gateway_status gcp_gateway_test gcp_gateway_down \
        gcp_pubsub_up gcp_pubsub_status gcp_pubsub_down \
        gcp_compute_up gcp_compute_status gcp_compute_ssh \
        gcp_compute_scp gcp_compute_down \
        setup_hooks \
        _check_uvr_env _check_synthetic_inputs _check_synthetic_export \
        _check_synthetic_cleaned_export _check_study_export \
        _check_study_cleaned_export

# ---------------------------------------------------------------------------
# Internal guards (not shown in help)
# ---------------------------------------------------------------------------

_check_uvr_env:
	@command -v uvr >/dev/null 2>&1 || { \
		echo "uvr not found. Run: bash ~/.dotfiles/scripts/setup-rust-uvr.sh"; \
		exit 1; \
	}
	@[ -f "$(ROOT)/uvr.toml" ] || { \
		echo "uvr.toml not found. Are you running from the project root?"; \
		echo "   Expected: $(ROOT)/uvr.toml"; \
		exit 1; \
	}
	@uvr_r_ver=$$(grep 'r_version' "$(ROOT)/uvr.toml" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1); \
	echo "R version (uvr): $$uvr_r_ver"

_check_synthetic_inputs:
	@import_dir="$(ROOT)/analysis/run_synthetic_data/data/import"; \
	n=$$(find "$$import_dir" -name "*.csv" 2>/dev/null | wc -l | tr -d ' '); \
	if [ "$$n" -eq 0 ]; then \
		echo "No CSV files found in analysis/run_synthetic_data/data/import/"; \
		echo "   Add input data files there before running synthetic analysis."; \
		exit 1; \
	fi; \
	echo "Found $$n input CSV(s) in data/import/"

_check_synthetic_export:
	@export_dir="$(ROOT)/analysis/run_synthetic_data/data/export"; \
	n=$$(find "$$export_dir" -name "syn_qualtrics_fct_panel_responses.csv" 2>/dev/null | wc -l | tr -d ' '); \
	if [ "$$n" -eq 0 ]; then \
		echo "No raw panel CSV found in analysis/run_synthetic_data/data/export/"; \
		echo "   Expected: syn_qualtrics_fct_panel_responses.csv"; \
		exit 1; \
	fi; \
	echo "Found raw panel export CSV in data/export/"

_check_synthetic_cleaned_export:
	@export_dir="$(ROOT)/analysis/run_synthetic_data/data/export"; \
	n=$$(find "$$export_dir" -name "syn_qualtrics_fct_panel_responses_cleaned.csv" 2>/dev/null | wc -l | tr -d ' '); \
	if [ "$$n" -eq 0 ]; then \
		echo "Cleaned panel CSV not found in analysis/run_synthetic_data/data/export/"; \
		echo "   Expected: syn_qualtrics_fct_panel_responses_cleaned.csv"; \
		echo "   Run: make synthetic_data_quality"; \
		exit 1; \
	fi; \
	echo "Found cleaned panel export CSV in data/export/"

_check_study_export:
	@export_dir="$(ROOT)/analysis/run_study_analysis/data/export"; \
	n=$$(find "$$export_dir" -name "qualtrics_fct_panel_responses.csv" 2>/dev/null | wc -l | tr -d ' '); \
	if [ "$$n" -eq 0 ]; then \
		echo "No raw panel CSV found in analysis/run_study_analysis/data/export/"; \
		echo "   Expected: qualtrics_fct_panel_responses.csv"; \
		echo "   Run: make study_export"; \
		exit 1; \
	fi; \
	echo "Found study raw panel CSV in data/export/"

_check_study_cleaned_export:
	@export_dir="$(ROOT)/analysis/run_study_analysis/data/export"; \
	n=$$(find "$$export_dir" -name "qualtrics_fct_panel_responses_cleaned.csv" 2>/dev/null | wc -l | tr -d ' '); \
	if [ "$$n" -eq 0 ]; then \
		echo "Cleaned study panel CSV not found in analysis/run_study_analysis/data/export/"; \
		echo "   Expected: qualtrics_fct_panel_responses_cleaned.csv"; \
		echo "   Run: make study_data_quality"; \
		exit 1; \
	fi; \
	echo "Found study cleaned panel CSV in data/export/"

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

help:
	@echo ""
	@echo "PhD Thesis -- Within-Person Fluctuation in Burnout and Turnover"
	@echo "$(AUTHOR)"
	@echo ""
	@echo "SETUP (run once on a new machine)"
	@echo "   make setup              Full setup: R env + Python deps"
	@echo "   make setup_r            R / uvr only (uvr sync)"
	@echo "   make setup_python       Python / uv only"
	@echo ""
	@echo "PRE-FLIGHT"
	@echo "   make validate           Static structure check (no packages needed)"
	@echo ""
	@echo "R ENVIRONMENT"
	@echo "   make uvr_sync           Install / restore packages from uvr.toml"
	@echo "   make uvr_lock           Regenerate uvr.lock without installing"
	@echo "   make uvr_status         Compare installed packages vs uvr.lock"
	@echo "   make uvr_doctor         Diagnose environment issues"
	@echo ""
	@echo "POWER ANALYSIS  (Arend & Schafer 2019)"
	@echo "   make power_analysis_dev          Dev grid, foreground (~seconds)"
	@echo "   make power_analysis_prod         Full local grid, 1,215 cells, background (~hours)"
	@echo "   make power_analysis_gcp_benchmark GCP timing probe; prod ~= benchmark x 100"
	@echo "   make power_analysis_gcp_prod     GCP full grid, 3,645 cells, background"
	@echo "   make power_analysis_gcp_posthoc  GCP post hoc supplement, 2,250 cells, background"
	@echo "   make power_visual                Power curve figures (after any run)"
	@echo ""
	@echo "SYNTHETIC DATA ANALYSIS"
	@echo "   make synthetic_analysis        Run steps 1-5 (data quality through MLM)"
	@echo "   make synthetic_data_quality    1. Careless responding detection + exclusions"
	@echo "   make synthetic_eda             2. Exploratory data analysis"
	@echo "   make synthetic_correlation     3. Correlation analysis"
	@echo "   make synthetic_measurement     4. Measurement model"
	@echo "   make synthetic_mlm             5. Multilevel model (main analysis)"
	@echo "   make synthetic_tables          6. Publication-ready Word tables"
	@echo ""
	@echo "STUDY DATA ANALYSIS"
	@echo "   make study_export              Rebuild BQ fact tables and re-export CSVs (prompts for confirmation)"
	@echo "   make study_all                 Full pipeline: quality -> analyses -> tables (guaranteed fresh)"
	@echo "   make study_analysis            Run steps 1-5 (data quality through MLM)"
	@echo "   make study_data_quality        1. Careless responding screening -> cleaned CSV"
	@echo "   make study_eda                 2. Exploratory data analysis"
	@echo "   make study_correlation         3. Correlation analysis"
	@echo "   make study_measurement         4. Measurement model (CFA)"
	@echo "   make study_mlm                 5. Multilevel model (main analysis)"
	@echo "   make study_tables              6. Publication-ready Word tables (.docx)"
	@echo ""
	@echo "PYTHON DEV"
	@echo "   make py_lint            ruff check + format check"
	@echo "   make py_format          Auto-fix formatting with ruff"
	@echo "   make py_sqlfmt          sqlfmt check"
	@echo "   make py_test            pytest gcp/tests/ -v"
	@echo ""
	@echo "GCP  (deploy from main branch only)"
	@echo "   make help_gcp           Full GCP deployment reference"
	@echo ""
	@echo "GCP COMPUTE VM"
	@echo "   make gcp_compute_up     Create power-analysis VM"
	@echo "   make gcp_compute_status Show VM state + external IP"
	@echo "   make gcp_compute_ssh    SSH into VM"
	@echo "   make gcp_compute_scp    Download results from VM"
	@echo "   make gcp_compute_down   Delete VM"
	@echo ""
	@echo "UTILITIES"
	@echo "   make status             File counts, git branch, lock file status"
	@echo "   make clean              Remove .tmp, .Rhistory, Rplots.pdf"
	@echo "   make welcome NAME=\"...\"  Personalized welcome message"
	@echo ""

help_gcp:
	@echo ""
	@echo "GCP DEPLOYMENT REFERENCE"
	@echo "   ALWAYS deploy from the main branch -- NEVER from a worktree."
	@echo "   Override the function name with FN=<name>  (default: $(FN))"
	@echo ""
	@echo "   Functions:"
	@echo "     run-qualtrics-scheduling   HTTP trigger, fronted by API Gateway"
	@echo "     run-intake-confirmation    Pub/Sub trigger"
	@echo "     run-followup-scheduling    Pub/Sub trigger"
	@echo "     run-followup-response      HTTP trigger, terminal inbound (/followup path)"
	@echo ""
	@echo "   Dev server:    make gcp_dev FN=run-qualtrics-scheduling"
	@echo "   Deploy:        make gcp_deploy FN=run-qualtrics-scheduling"
	@echo ""
	@echo "   Infrastructure:"
	@echo "     make gcp_infra_up          Create BigQuery tables"
	@echo "     make gcp_infra_status      Show table state"
	@echo "     make gcp_infra_down        Tear down BigQuery tables"
	@echo "     make gcp_pubsub_up         Create Pub/Sub topics"
	@echo "     make gcp_pubsub_status     Show topic state and subscriptions"
	@echo "     make gcp_pubsub_down       Tear down Pub/Sub topics"
	@echo ""
	@echo "   API Gateway:"
	@echo "     make gcp_gateway_up        Set up API Gateway"
	@echo "     make gcp_gateway_status    Show current gateway resource state"
	@echo "     make gcp_gateway_test               End-to-end test (fixed survey times)"
	@echo "     make gcp_gateway_test PHONE=16xxxxxxxx  E2E test, real SMS to your phone"
	@echo "     make gcp_gateway_test NOW=1         E2E test (schedule at now+16/32/48 min)"
	@echo "     make gcp_gateway_test FOLLOWUP=1    Smoke test POST /followup (default fixture)"
	@echo "     make gcp_gateway_test FOLLOWUP=1 TP=1  Smoke test p1/9AM fixture"
	@echo "     make gcp_gateway_test FOLLOWUP=1 TP=2  Smoke test p2/1PM fixture"
	@echo "     make gcp_gateway_test FOLLOWUP=1 TP=3  Smoke test p3/5PM fixture"
	@echo "     make gcp_gateway_down      Tear down API Gateway"
	@echo ""
	@echo "   Schema change workflow:"
	@echo "     Intake:   models/qualtrics.py -> bq_schemas.py -> web_service_payload.json"
	@echo "               -> test_models.py -> make gcp_infra_down && make gcp_infra_up"
	@echo "     Followup: models/followup.py -> bq_schemas.py -> followup_web_service_payload.json"
	@echo "               -> test_followup_response.py -> make gcp_infra_down && make gcp_infra_up"
	@echo ""

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

setup: setup_r setup_python setup_hooks
	@echo ""
	@echo "Full setup complete. Run 'make validate' to verify the structure."

setup_r: _check_uvr_env
	@echo "Setting up R environment via uvr..."
	@echo ""
	@cd "$(ROOT)" && uvr sync || { \
		echo ""; \
		echo "uvr sync failed."; \
		echo "   Check uvr.toml for invalid package specs."; \
		echo "   Run: uvr doctor"; \
		exit 1; \
	}
	@echo ""
	@echo "R environment ready."

setup_python:
	@command -v uv >/dev/null 2>&1 || { \
		echo "uv not found."; \
		echo "   Install: https://docs.astral.sh/uv/getting-started/installation/"; \
		exit 1; \
	}
	@cd "$(ROOT)" && uv lock --check || { \
		echo "uv.lock is out of sync with pyproject.toml."; \
		echo "   Run: uv lock"; \
		exit 1; \
	}
	@echo "Installing Python dependencies..."
	@cd "$(ROOT)" && uv sync || { \
		echo "uv sync failed"; \
		exit 1; \
	}
	@echo "Python environment ready."

setup_hooks:
	@mkdir -p "$(ROOT)/scripts/hooks"
	@if [ -d "$(ROOT)/.git" ]; then \
		mkdir -p "$(ROOT)/.git/hooks"; \
		ln -sf "$(ROOT)/scripts/hooks/pre-commit" "$(ROOT)/.git/hooks/pre-commit"; \
		chmod +x "$(ROOT)/scripts/hooks/pre-commit"; \
		echo "Pre-commit hook installed (blocks accidental lock file commits)."; \
		echo "   Bypass: ALLOW_LOCK_COMMIT=1 git commit ..."; \
	else \
		echo "No .git directory found -- hooks skipped (archive checkout?)."; \
		echo "   To install manually: ln -sf \$$(pwd)/scripts/hooks/pre-commit .git/hooks/pre-commit"; \
	fi

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------

validate:
	@echo "Running static structure validation (no packages needed)..."
	@echo ""
	@bash "$(ROOT)/analysis/tests/validate_r_structure.sh" || { \
		echo ""; \
		echo "Validation failed. Fix reported issues before running analyses."; \
		exit 1; \
	}

# ---------------------------------------------------------------------------
# R Environment (uvr)
# ---------------------------------------------------------------------------

uvr_sync: _check_uvr_env
	@echo "Installing / restoring R packages from uvr.toml..."
	@echo ""
	@cd "$(ROOT)" && uvr sync || { \
		echo ""; \
		echo "uvr sync failed."; \
		echo "   Run: uvr doctor"; \
		exit 1; \
	}
	@echo ""
	@echo "R environment synced."

uvr_lock: _check_uvr_env
	@echo "Regenerating uvr.lock from uvr.toml (no install)..."
	@echo ""
	@cd "$(ROOT)" && uvr lock || { \
		echo "uvr lock failed."; \
		exit 1; \
	}
	@echo ""
	@echo "uvr.lock updated. Review: git diff uvr.lock"

uvr_status: _check_uvr_env
	@echo "Checking uvr environment status..."
	@echo ""
	@cd "$(ROOT)" && uvr status || { \
		echo "uvr status failed -- environment may be incomplete."; \
		echo "   Run: make uvr_sync"; \
		exit 1; \
	}

uvr_doctor: _check_uvr_env
	@echo "Running uvr doctor..."
	@echo ""
	@cd "$(ROOT)" && uvr doctor

# ---------------------------------------------------------------------------
# Power Analysis
# ---------------------------------------------------------------------------

power_analysis_dev: _check_uvr_env validate
	@echo "Running power analysis (dev grid) -- foreground, logs to terminal + file..."
	@echo ""
	@bash "$(ROOT)/analysis/run_power_analysis/main.sh" dev || { \
		echo ""; \
		echo "Power analysis (dev) failed. Check logs in:"; \
		echo "   analysis/run_power_analysis/logs/"; \
		exit 1; \
	}
	@echo ""
	@echo "Power analysis (dev) complete."

power_analysis_prod: _check_uvr_env validate
	@echo "Starting power analysis (full grid) in background..."
	@echo ""
	@echo "This takes hours. Do NOT run from a worktree -- output paths may collide."
	@echo ""
	@mkdir -p "$(ROOT)/analysis/run_power_analysis/logs"
	@nohup bash "$(ROOT)/analysis/run_power_analysis/main.sh" prod \
		> "$(ROOT)/analysis/run_power_analysis/logs/prod_$$(date +%Y%m%d_%H%M%S).log" 2>&1 & \
	echo "Power analysis started with PID: $$!"; \
	echo "   Monitor: tail -f analysis/run_power_analysis/logs/*.log"

power_analysis_gcp_benchmark: _check_uvr_env validate
	@echo "Running GCP benchmark (timing probe)..."
	@echo ""
	@bash "$(ROOT)/analysis/run_power_analysis/main.sh" benchmark_gcp || { \
		echo ""; \
		echo "GCP benchmark failed. Check logs in:"; \
		echo "   analysis/run_power_analysis/logs/"; \
		exit 1; \
	}
	@echo ""
	@echo "GCP benchmark complete."

power_analysis_gcp_prod: _check_uvr_env validate
	@echo "Starting GCP power analysis (full grid) in background..."
	@echo ""
	@mkdir -p "$(ROOT)/analysis/run_power_analysis/logs"
	@nohup bash "$(ROOT)/analysis/run_power_analysis/main.sh" prod_gcp \
		> "$(ROOT)/analysis/run_power_analysis/logs/prod_gcp_$$(date +%Y%m%d_%H%M%S).log" 2>&1 & \
	echo "GCP power analysis started with PID: $$!"; \
	echo "   Monitor: tail -f analysis/run_power_analysis/logs/*.log"

power_analysis_gcp_posthoc: _check_uvr_env validate
	@echo "Starting GCP post hoc power analysis (2,250-cell supplement) in background..."
	@echo ""
	@mkdir -p "$(ROOT)/analysis/run_power_analysis/logs"
	@nohup bash "$(ROOT)/analysis/run_power_analysis/main.sh" posthoc_gcp \
		> "$(ROOT)/analysis/run_power_analysis/logs/posthoc_gcp_$$(date +%Y%m%d_%H%M%S).log" 2>&1 & \
	echo "GCP post hoc power analysis started with PID: $$!"; \
	echo "   Monitor: tail -f analysis/run_power_analysis/logs/*.log"

power_visual: _check_uvr_env
	@echo "Generating power analysis visualizations..."
	@$(RSCRIPT) "$(ROOT)/analysis/run_power_analysis/scripts/visualize_power_analysis.r" || { \
		echo "visualize_power_analysis.r failed"; \
		exit 1; \
	}
	@echo "Visualizations complete. Figures -> analysis/run_power_analysis/figs/"

# ---------------------------------------------------------------------------
# Synthetic Data Analysis
# ---------------------------------------------------------------------------

synthetic_data_quality: _check_uvr_env _check_synthetic_export
	@echo "Running data quality screening (careless responding)..."
	@$(RSCRIPT) "$(ROOT)/analysis/run_synthetic_data/scripts/r/data_quality.r" || { \
		echo "data_quality.r failed"; \
		exit 1; \
	}
	@echo "Data quality complete. Cleaned CSV -> analysis/run_synthetic_data/data/export/"
	@echo "   Diagnostics  -> analysis/run_synthetic_data/figs/data_quality/"

synthetic_eda: _check_uvr_env _check_synthetic_cleaned_export
	@echo "Running EDA script..."
	@$(RSCRIPT) "$(ROOT)/analysis/run_synthetic_data/scripts/r/eda.r" || { \
		echo "eda.r failed"; \
		exit 1; \
	}
	@echo "EDA complete. Figures -> analysis/run_synthetic_data/figs/eda/"

synthetic_measurement: _check_uvr_env _check_synthetic_cleaned_export
	@echo "Running measurement model..."
	@$(RSCRIPT) "$(ROOT)/analysis/run_synthetic_data/scripts/r/measurement_model.r" || { \
		echo "measurement_model.r failed"; \
		exit 1; \
	}
	@echo "Measurement model complete."

synthetic_mlm: _check_uvr_env _check_synthetic_cleaned_export
	@echo "Running multilevel model (main analysis)..."
	@$(RSCRIPT) "$(ROOT)/analysis/run_synthetic_data/scripts/r/multilevel_model.r" || { \
		echo "multilevel_model.r failed"; \
		exit 1; \
	}
	@echo "MLM complete. Figures -> analysis/run_synthetic_data/figs/mlm/"

synthetic_correlation: _check_uvr_env _check_synthetic_cleaned_export
	@echo "Running correlation analysis..."
	@$(RSCRIPT) "$(ROOT)/analysis/run_synthetic_data/scripts/r/correlation.r" || { \
		echo "correlation.r failed"; \
		exit 1; \
	}
	@echo "Correlation analysis complete. Figures -> analysis/run_synthetic_data/figs/corr/"

synthetic_analysis: synthetic_data_quality synthetic_eda synthetic_correlation synthetic_measurement synthetic_mlm
	@echo ""
	@echo "All synthetic data analyses complete."

synthetic_tables: _check_uvr_env _check_synthetic_cleaned_export
	@echo "Generating publication tables..."
	@$(RSCRIPT) "$(ROOT)/analysis/run_synthetic_data/scripts/r/publication_tables.r" || { \
		echo "publication_tables.r failed"; \
		exit 1; \
	}
	@echo "Publication tables -> analysis/run_synthetic_data/tables/"

# ---------------------------------------------------------------------------
# Study Data Analysis
# ---------------------------------------------------------------------------

study_export:
	@read -p "Rebuild BQ fact tables and re-export CSVs? This overwrites data/export/. [y/N] " confirm; \
	[ "$$confirm" = "y" ] || { echo "Aborted."; exit 1; }; \
	bash "$(ROOT)/analysis/run_study_analysis/scripts/export_study_participation_summary_csv.sh" && \
	bash "$(ROOT)/analysis/run_study_analysis/scripts/export_study_fct_panel_responses_csv.sh"

study_data_quality: _check_uvr_env _check_study_export
	@echo "Running study data quality screening..."
	@$(RSCRIPT) "$(ROOT)/analysis/run_study_analysis/scripts/R/data_quality.r" || { \
		echo "data_quality.r failed"; \
		exit 1; \
	}
	@echo "Data quality complete. Cleaned CSV -> analysis/run_study_analysis/data/export/"
	@echo "   Diagnostics  -> analysis/run_study_analysis/figs/data_quality/"

study_eda: _check_uvr_env _check_study_cleaned_export
	@echo "Running study EDA..."
	@$(RSCRIPT) "$(ROOT)/analysis/run_study_analysis/scripts/R/eda.r" || { \
		echo "eda.r failed"; \
		exit 1; \
	}
	@echo "EDA complete. Figures -> analysis/run_study_analysis/figs/eda/"

study_measurement: _check_uvr_env _check_study_cleaned_export
	@echo "Running study measurement model..."
	@$(RSCRIPT) "$(ROOT)/analysis/run_study_analysis/scripts/R/measurement_model.r" || { \
		echo "measurement_model.r failed"; \
		exit 1; \
	}
	@echo "Measurement model complete. Figures -> analysis/run_study_analysis/figs/cfa/"

study_mlm: _check_uvr_env _check_study_cleaned_export
	@echo "Running study multilevel model..."
	@$(RSCRIPT) "$(ROOT)/analysis/run_study_analysis/scripts/R/multilevel_model.r" || { \
		echo "multilevel_model.r failed"; \
		exit 1; \
	}
	@echo "MLM complete. Figures -> analysis/run_study_analysis/figs/mlm/"

study_correlation: _check_uvr_env _check_study_cleaned_export
	@echo "Running study correlation analysis..."
	@$(RSCRIPT) "$(ROOT)/analysis/run_study_analysis/scripts/R/correlation.r" || { \
		echo "correlation.r failed"; \
		exit 1; \
	}
	@echo "Correlation complete. Figures -> analysis/run_study_analysis/figs/corr/"

study_analysis: study_data_quality study_eda study_correlation study_measurement study_mlm
	@echo ""
	@echo "All study data analyses complete."

study_all: _check_uvr_env _check_study_export study_analysis study_tables
	@echo ""
	@echo "Full study pipeline complete (data quality -> analyses -> tables)."

study_tables: _check_uvr_env _check_study_cleaned_export
	@echo "Generating study publication tables..."
	@$(RSCRIPT) "$(ROOT)/analysis/run_study_analysis/scripts/R/publication_tables.r" || { \
		echo "publication_tables.r failed"; \
		exit 1; \
	}
	@echo "Publication tables -> analysis/run_study_analysis/tables/"

# ---------------------------------------------------------------------------
# Python Dev
# ---------------------------------------------------------------------------

py_lint:
	@echo "Running ruff check..."
	@cd "$(ROOT)" && uv run ruff check . && echo "ruff check passed"
	@echo ""
	@echo "Checking ruff format..."
	@cd "$(ROOT)" && uv run ruff format --check . && echo "ruff format check passed"

py_format:
	@echo "Auto-formatting with ruff..."
	@cd "$(ROOT)" && uv run ruff check --fix . && uv run ruff format .
	@echo "Formatting complete."

py_sqlfmt:
	@echo "Running sqlfmt check..."
	@cd "$(ROOT)" && uv run sqlfmt --check . && echo "sqlfmt passed"

py_test:
	@echo "Running Python tests..."
	@cd "$(ROOT)" && uv run pytest gcp/tests/ -v

# ---------------------------------------------------------------------------
# GCP
# ---------------------------------------------------------------------------

gcp_dev:
	@echo "Starting local dev server for: $(FN)"
	@echo "   (Override with: make gcp_dev FN=run_intake_confirmation)"
	@echo ""
	@cd "$(ROOT)" && uv run gcp/deploy/manage_functions.py dev $(FN)

gcp_deploy:
	@echo "Deploying $(FN) to GCP..."
	@echo ""
	@echo "Current branch: $$(git -C "$(ROOT)" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
	@echo "   Deploy from main only -- never from a worktree."
	@echo ""
	@cd "$(ROOT)" && uv run gcp/deploy/manage_functions.py deploy $(FN)

gcp_infra_up:
	@echo "Setting up BigQuery tables..."
	@cd "$(ROOT)" && uv run gcp/deploy/manage_infra.py setup

gcp_infra_status:
	@echo "BigQuery table state..."
	@cd "$(ROOT)" && uv run gcp/deploy/manage_infra.py status

gcp_infra_down:
	@echo "Tearing down BigQuery tables..."
	@cd "$(ROOT)" && uv run gcp/deploy/manage_infra.py teardown

gcp_gateway_up:
	@echo "Setting up API Gateway..."
	@cd "$(ROOT)" && uv run gcp/deploy/manage_gateway.py setup

gcp_gateway_status:
	@echo "API Gateway resource state..."
	@cd "$(ROOT)" && uv run gcp/deploy/manage_gateway.py status

gcp_gateway_test:
	@echo "Running gateway test..."
	@if [ "$(FOLLOWUP)" = "1" ] && [ -n "$(TP)" ]; then \
		echo "   Mode: followup smoke test (timepoint $(TP))"; \
		cd "$(ROOT)" && uv run gcp/deploy/manage_gateway.py test --followup --timepoint $(TP); \
	elif [ "$(FOLLOWUP)" = "1" ]; then \
		echo "   Mode: followup smoke test (default fixture)"; \
		cd "$(ROOT)" && uv run gcp/deploy/manage_gateway.py test --followup; \
	elif [ -n "$(PHONE)" ]; then \
		echo "   Mode: now-with-me (real SMS to $(PHONE))"; \
		cd "$(ROOT)" && uv run gcp/deploy/manage_gateway.py test --now-with-me $(PHONE); \
	elif [ "$(NOW)" = "1" ]; then \
		echo "   Mode: now+16/32/48 min (--now)"; \
		cd "$(ROOT)" && uv run gcp/deploy/manage_gateway.py test --now; \
	else \
		echo "   Mode: fixed survey times  (use NOW=1 for rapid scheduling)"; \
		cd "$(ROOT)" && uv run gcp/deploy/manage_gateway.py test; \
	fi

gcp_gateway_down:
	@echo "Tearing down API Gateway..."
	@cd "$(ROOT)" && uv run gcp/deploy/manage_gateway.py teardown

gcp_pubsub_up:
	@echo "Setting up Pub/Sub topics..."
	@cd "$(ROOT)" && uv run gcp/deploy/manage_pubsub.py setup

gcp_pubsub_status:
	@echo "Pub/Sub topic state..."
	@cd "$(ROOT)" && uv run gcp/deploy/manage_pubsub.py status

gcp_pubsub_down:
	@echo "Tearing down Pub/Sub topics..."
	@cd "$(ROOT)" && uv run gcp/deploy/manage_pubsub.py teardown

gcp_compute_up:
	@echo "Creating power-analysis VM..."
	@cd "$(ROOT)" && uv run gcp/deploy/manage_compute.py setup

gcp_compute_status:
	@echo "Checking VM status..."
	@cd "$(ROOT)" && uv run gcp/deploy/manage_compute.py status

gcp_compute_ssh:
	@echo "SSH into power-analysis VM..."
	@cd "$(ROOT)" && uv run gcp/deploy/manage_compute.py ssh

gcp_compute_scp:
	@echo "Downloading results from VM..."
	@cd "$(ROOT)" && uv run gcp/deploy/manage_compute.py scp

gcp_compute_down:
	@echo "Deleting power-analysis VM..."
	@cd "$(ROOT)" && uv run gcp/deploy/manage_compute.py teardown

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

status:
	@echo "Project Status"
	@echo ""
	@echo "Metadata:"
	@echo "   Version : $(VERSION)"
	@echo "   Author  : $(AUTHOR)"
	@echo ""
	@echo "File counts:"
	@echo "   R scripts    : $$(find "$(ROOT)/analysis" -name '*.r' 2>/dev/null | wc -l | tr -d ' ') found"
	@echo "   YAML configs : $$(find "$(ROOT)/analysis" -name '*.yaml' 2>/dev/null | wc -l | tr -d ' ') found"
	@echo "   CSV data     : $$(find "$(ROOT)/analysis" -name '*.csv' 2>/dev/null | wc -l | tr -d ' ') found"
	@echo "   Python files : $$(find "$(ROOT)/gcp" -name '*.py' 2>/dev/null | wc -l | tr -d ' ') found"
	@echo ""
	@echo "Lock files:"
	@if [ -f "$(ROOT)/uvr.toml" ]; then \
		echo "   uvr.toml     ok"; \
	else \
		echo "   uvr.toml     MISSING"; \
	fi
	@if [ -f "$(ROOT)/uvr.lock" ]; then \
		echo "   uvr.lock     ok  ($$(wc -l < "$(ROOT)/uvr.lock" | tr -d ' ') lines)"; \
	else \
		echo "   uvr.lock     absent (run: make uvr_sync)"; \
	fi
	@if [ -f "$(ROOT)/uv.lock" ]; then \
		echo "   uv.lock      ok  ($$(wc -l < "$(ROOT)/uv.lock" | tr -d ' ') lines)"; \
	else \
		echo "   uv.lock      MISSING"; \
	fi
	@echo ""
	@echo "Git:"
	@echo "   Branch : $$(git -C "$(ROOT)" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'not a git repo')"

clean:
	@echo "Cleaning temporary files..."
	@find "$(ROOT)" -name "*.tmp" -delete 2>/dev/null || true
	@find "$(ROOT)" -name ".Rhistory" -delete 2>/dev/null || true
	@find "$(ROOT)" -name "Rplots.pdf" -delete 2>/dev/null || true
	@find "$(ROOT)" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@echo "Cleanup complete."

welcome:
ifndef NAME
	@echo "Name required!"
	@echo "   Usage: make welcome NAME=\"Your Name\""
else
	@echo ""
	@echo "Hola buenas, $(NAME)! Encantado conocerte."
	@echo ""
	@echo "Welcome to my doctoral thesis research project:"
	@echo "$(PROJECT_NAME)"
	@echo ""
	@echo "Version: $(VERSION)   |   Author: $(AUTHOR)"
	@echo ""
	@echo "Project structure:"
	@echo "   analysis/run_power_analysis/    MLM power simulations (R)"
	@echo "   analysis/run_synthetic_data/    Synthetic ESM data analysis (R)"
	@echo "   gcp/                            Cloud Run data collection pipeline (Python)"
	@echo "   uvr.toml                        R package manifest"
	@echo "   pyproject.toml                  Python uv config"
	@echo ""
	@echo "Quick start for replicators:"
	@echo "   make setup                      Set up R + Python environments"
	@echo "   make validate                   Pre-flight structure check"
	@echo "   make power_analysis_dev         Run power analysis (dev grid)"
	@echo "   make synthetic_analysis         Run all synthetic data analyses"
	@echo "   make help                       Full command reference"
	@echo ""
	@echo "Ready to get started, $(NAME)!"
endif
