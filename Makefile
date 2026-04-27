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

# Default GCP function; override: make gcp_dev FN=run_intake_confirmation
FN ?= run_qualtrics_scheduling

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
        power_visual \
        synthetic_analysis synthetic_data_quality \
        synthetic_eda synthetic_measurement \
        synthetic_mlm synthetic_correlation synthetic_tables \
        py_lint py_format py_sqlfmt py_test \
        gcp_dev gcp_deploy \
        gcp_infra_up gcp_infra_status gcp_infra_down \
        gcp_gateway_up gcp_gateway_status gcp_gateway_test gcp_gateway_down \
        gcp_pubsub_up gcp_pubsub_status gcp_pubsub_down \
        gcp_compute_up gcp_compute_status gcp_compute_ssh \
        gcp_compute_scp gcp_compute_down \
        setup_hooks \
        _check_uvr_env _check_synthetic_inputs _check_synthetic_export

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
	@echo "     run_qualtrics_scheduling   HTTP trigger, fronted by API Gateway"
	@echo "     run_intake_confirmation    Pub/Sub trigger"
	@echo "     run_followup_scheduling    Pub/Sub trigger"
	@echo "     run_followup_response      HTTP trigger, terminal inbound (/followup path)"
	@echo ""
	@echo "   Dev server:    make gcp_dev FN=run_qualtrics_scheduling"
	@echo "   Deploy:        make gcp_deploy FN=run_qualtrics_scheduling"
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
	@echo "     make gcp_gateway_test      End-to-end test (fixed survey times)"
	@echo "     make gcp_gateway_test NOW=1  E2E test (schedule at now+16/32/48 min)"
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
	@cd "$(ROOT)" && uv sync --all-groups || { \
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

power_visual: _check_uvr_env
	@echo "Generating power analysis visualizations..."
	@$(RSCRIPT) "$(ROOT)/analysis/run_power_analysis/scripts/visualize_power_analysis.R" || { \
		echo "visualize_power_analysis.R failed"; \
		exit 1; \
	}
	@echo "Visualizations complete. Figures -> analysis/run_power_analysis/figs/"

# ---------------------------------------------------------------------------
# Synthetic Data Analysis
# ---------------------------------------------------------------------------

synthetic_data_quality: _check_uvr_env _check_synthetic_export
	@echo "Running data quality screening (careless responding)..."
	@$(RSCRIPT) "$(ROOT)/analysis/run_synthetic_data/scripts/r/data_quality.R" || { \
		echo "data_quality.R failed"; \
		exit 1; \
	}
	@echo "Data quality complete. Cleaned CSV -> analysis/run_synthetic_data/data/export/"
	@echo "   Diagnostics  -> analysis/run_synthetic_data/figs/data_quality/"

synthetic_eda: _check_uvr_env _check_synthetic_inputs
	@echo "Running EDA script..."
	@$(RSCRIPT) "$(ROOT)/analysis/run_synthetic_data/scripts/r/eda.R" || { \
		echo "eda.R failed"; \
		exit 1; \
	}
	@echo "EDA complete. Figures -> analysis/run_synthetic_data/figs/eda/"

synthetic_measurement: _check_uvr_env _check_synthetic_inputs
	@echo "Running measurement model..."
	@$(RSCRIPT) "$(ROOT)/analysis/run_synthetic_data/scripts/r/measurement_model.R" || { \
		echo "measurement_model.R failed"; \
		exit 1; \
	}
	@echo "Measurement model complete."

synthetic_mlm: _check_uvr_env _check_synthetic_inputs
	@echo "Running multilevel model (main analysis)..."
	@$(RSCRIPT) "$(ROOT)/analysis/run_synthetic_data/scripts/r/multilevel_model.R" || { \
		echo "multilevel_model.R failed"; \
		exit 1; \
	}
	@echo "MLM complete. Figures -> analysis/run_synthetic_data/figs/mlm/"

synthetic_correlation: _check_uvr_env _check_synthetic_inputs
	@echo "Running correlation analysis..."
	@$(RSCRIPT) "$(ROOT)/analysis/run_synthetic_data/scripts/r/correlation.R" || { \
		echo "correlation.R failed"; \
		exit 1; \
	}
	@echo "Correlation analysis complete. Figures -> analysis/run_synthetic_data/figs/corr/"

synthetic_analysis: synthetic_data_quality synthetic_eda synthetic_correlation synthetic_measurement synthetic_mlm
	@echo ""
	@echo "All synthetic data analyses complete."

synthetic_tables: _check_uvr_env _check_synthetic_inputs
	@echo "Generating publication tables..."
	@$(RSCRIPT) "$(ROOT)/analysis/run_synthetic_data/scripts/r/publication_tables.R" || { \
		echo "publication_tables.R failed"; \
		exit 1; \
	}
	@echo "Publication tables -> analysis/run_synthetic_data/tables/"

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
	@cd "$(ROOT)" && python gcp/deploy/manage_functions.py dev $(FN)

gcp_deploy:
	@echo "Deploying $(FN) to GCP..."
	@echo ""
	@echo "Current branch: $$(git -C "$(ROOT)" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
	@echo "   Deploy from main only -- never from a worktree."
	@echo ""
	@cd "$(ROOT)" && python gcp/deploy/manage_functions.py deploy $(FN)

gcp_infra_up:
	@echo "Setting up BigQuery tables..."
	@cd "$(ROOT)" && python gcp/deploy/manage_infra.py setup

gcp_infra_status:
	@echo "BigQuery table state..."
	@cd "$(ROOT)" && python gcp/deploy/manage_infra.py status

gcp_infra_down:
	@echo "Tearing down BigQuery tables..."
	@cd "$(ROOT)" && python gcp/deploy/manage_infra.py teardown

gcp_gateway_up:
	@echo "Setting up API Gateway..."
	@cd "$(ROOT)" && python gcp/deploy/manage_gateway.py setup

gcp_gateway_status:
	@echo "API Gateway resource state..."
	@cd "$(ROOT)" && python gcp/deploy/manage_gateway.py status

gcp_gateway_test:
	@echo "Running end-to-end gateway test..."
	@if [ "$(NOW)" = "1" ]; then \
		echo "   Mode: now+16/32/48 min (--now)"; \
		cd "$(ROOT)" && python gcp/deploy/manage_gateway.py test --now; \
	else \
		echo "   Mode: fixed survey times  (use NOW=1 for rapid scheduling)"; \
		cd "$(ROOT)" && python gcp/deploy/manage_gateway.py test; \
	fi

gcp_gateway_down:
	@echo "Tearing down API Gateway..."
	@cd "$(ROOT)" && python gcp/deploy/manage_gateway.py teardown

gcp_pubsub_up:
	@echo "Setting up Pub/Sub topics..."
	@cd "$(ROOT)" && python gcp/deploy/manage_pubsub.py setup

gcp_pubsub_status:
	@echo "Pub/Sub topic state..."
	@cd "$(ROOT)" && python gcp/deploy/manage_pubsub.py status

gcp_pubsub_down:
	@echo "Tearing down Pub/Sub topics..."
	@cd "$(ROOT)" && python gcp/deploy/manage_pubsub.py teardown

gcp_compute_up:
	@echo "Creating power-analysis VM..."
	@cd "$(ROOT)" && python gcp/deploy/manage_compute.py setup

gcp_compute_status:
	@echo "Checking VM status..."
	@cd "$(ROOT)" && python gcp/deploy/manage_compute.py status

gcp_compute_ssh:
	@echo "SSH into power-analysis VM..."
	@cd "$(ROOT)" && python gcp/deploy/manage_compute.py ssh

gcp_compute_scp:
	@echo "Downloading results from VM..."
	@cd "$(ROOT)" && python gcp/deploy/manage_compute.py scp

gcp_compute_down:
	@echo "Deleting power-analysis VM..."
	@cd "$(ROOT)" && python gcp/deploy/manage_compute.py teardown

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
	@echo "   R scripts    : $$(find "$(ROOT)/analysis" -name '*.r' -o -name '*.R' 2>/dev/null | wc -l | tr -d ' ') found"
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
