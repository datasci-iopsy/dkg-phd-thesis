# Project information
PROJECT_NAME := "If You Only Knew the Power of the Dark Side": Examining Within-Person \
  Fluctuation in Psychological Need Frustration, Burnout, and Turnover Intentions \
  Across a Workday
VERSION      := 1.0.0
AUTHOR       := Demetrius K. Green, ABD

# Absolute project root — prevents cd-induced relative path bugs
ROOT := $(CURDIR)

# Default GCP function; override: make gcp_dev FN=run_intake_confirmation
FN ?= run_qualtrics_scheduling

.DEFAULT_GOAL := help

# ---------------------------------------------------------------------------
# .PHONY declarations
# ---------------------------------------------------------------------------
.PHONY: help help_gcp welcome status clean \
        setup setup_r setup_python \
        validate \
        renv_restore renv_status renv_repair renv_snapshot \
        power_analysis_dev power_analysis_prod power_analysis_prod_set1 \
        synthetic_analysis synthetic_eda synthetic_measurement \
        synthetic_mlm synthetic_correlation \
        py_install py_lint py_format py_sqlfmt py_test \
        gcp_dev gcp_deploy \
        gcp_infra_up gcp_infra_down \
        gcp_gateway_up gcp_gateway_test gcp_gateway_down \
        gcp_pubsub_up gcp_pubsub_down \
        _check_r_env _check_synthetic_inputs

# ---------------------------------------------------------------------------
# Internal guards (not shown in help)
# ---------------------------------------------------------------------------

_check_r_env:
	@command -v Rscript >/dev/null 2>&1 || { \
		echo "❌ Rscript not found. Install R 4.4: https://cran.r-project.org/"; \
		exit 1; \
	}
	@r_ver=$$(Rscript --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1); \
	echo "ℹ️  R version: $$r_ver"; \
	r_major=$$(echo "$$r_ver" | cut -d. -f1); \
	r_minor=$$(echo "$$r_ver" | cut -d. -f2); \
	if [ "$$r_major" -lt 4 ] || { [ "$$r_major" -eq 4 ] && [ "$$r_minor" -lt 4 ]; }; then \
		echo "⚠️  R >= 4.4 required; got $$r_ver — proceed with caution."; \
	fi
	@[ -f "$(ROOT)/renv.lock" ] || { \
		echo "❌ renv.lock not found. Are you running from the project root?"; \
		echo "   Expected: $(ROOT)/renv.lock"; \
		exit 1; \
	}

_check_synthetic_inputs:
	@import_dir="$(ROOT)/analysis/run_synthetic_data/data/import"; \
	n=$$(find "$$import_dir" -name "*.csv" 2>/dev/null | wc -l | tr -d ' '); \
	if [ "$$n" -eq 0 ]; then \
		echo "❌ No CSV files found in analysis/run_synthetic_data/data/import/"; \
		echo "   Add input data files there before running synthetic analysis."; \
		exit 1; \
	fi; \
	echo "ℹ️  Found $$n input CSV(s) in data/import/"

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

help:
	@echo ""
	@echo "╔══════════════════════════════════════════════════════════════════════╗"
	@echo "║   PhD Thesis — Within-Person Fluctuation in Burnout & Turnover      ║"
	@echo "║   $(AUTHOR)                                            ║"
	@echo "╚══════════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🚀 SETUP (run once on a new machine)"
	@echo "   make setup              Full setup: R env + Python deps"
	@echo "   make setup_r            R / renv only"
	@echo "   make setup_python       Python / Poetry only"
	@echo ""
	@echo "✅ PRE-FLIGHT"
	@echo "   make validate           Static structure check (no packages needed)"
	@echo ""
	@echo "🔧 R ENVIRONMENT"
	@echo "   make renv_restore       Restore packages from renv.lock"
	@echo "   make renv_status        Compare installed packages vs renv.lock"
	@echo "   make renv_repair        Fix broken cache/symlinks, then restore"
	@echo "   make renv_snapshot      Update renv.lock from current environment"
	@echo ""
	@echo "📊 POWER ANALYSIS  (Arend & Schafer 2019)"
	@echo "   make power_analysis_dev         Dev grid, foreground (~seconds)"
	@echo "   make power_analysis_prod        Set 2 of 2, background via nohup (~hours)"
	@echo "   make power_analysis_prod_set1   Set 1 of 2, background via nohup (~hours)"
	@echo "   Run both prod targets simultaneously for the full 2,430-cell grid"
	@echo ""
	@echo "🔬 SYNTHETIC DATA ANALYSIS"
	@echo "   make synthetic_analysis    Run all four scripts in sequence"
	@echo "   make synthetic_eda         1. Exploratory data analysis"
	@echo "   make synthetic_correlation 2. Correlation analysis"
	@echo "   make synthetic_measurement 3. Measurement model"
	@echo "   make synthetic_mlm         4. Multilevel model (main analysis)"
	@echo ""
	@echo "🐍 PYTHON DEV"
	@echo "   make py_lint            ruff check + format check"
	@echo "   make py_format          Auto-fix formatting with ruff"
	@echo "   make py_sqlfmt          sqlfmt check"
	@echo "   make py_test            pytest gcp/tests/ -v"
	@echo ""
	@echo "☁️  GCP  (deploy from main branch only)"
	@echo "   make help_gcp           Full GCP deployment reference"
	@echo ""
	@echo "🔍 UTILITIES"
	@echo "   make status             File counts, git branch, lock file status"
	@echo "   make clean              Remove .tmp, .Rhistory, Rplots.pdf"
	@echo "   make welcome NAME=\"…\"   Personalized welcome message"
	@echo ""

help_gcp:
	@echo ""
	@echo "☁️  GCP DEPLOYMENT REFERENCE"
	@echo "   ⚠️  ALWAYS deploy from the main branch — NEVER from a worktree."
	@echo "   Override the function name with FN=<name>  (default: $(FN))"
	@echo ""
	@echo "   Functions:"
	@echo "     run_qualtrics_scheduling   HTTP trigger, fronted by API Gateway"
	@echo "     run_intake_confirmation    Pub/Sub trigger"
	@echo "     run_followup_scheduling    Pub/Sub trigger"
	@echo ""
	@echo "   Dev server:    make gcp_dev FN=run_qualtrics_scheduling"
	@echo "   Deploy:        make gcp_deploy FN=run_qualtrics_scheduling"
	@echo ""
	@echo "   Infrastructure:"
	@echo "     make gcp_infra_up          Create BigQuery tables"
	@echo "     make gcp_infra_down        Tear down BigQuery tables"
	@echo "     make gcp_pubsub_up         Create Pub/Sub topics"
	@echo "     make gcp_pubsub_down       Tear down Pub/Sub topics"
	@echo ""
	@echo "   API Gateway:"
	@echo "     make gcp_gateway_up        Set up API Gateway"
	@echo "     make gcp_gateway_test      End-to-end test (fixed survey times)"
	@echo "     make gcp_gateway_test NOW=1  E2E test (schedule at now+16/32/48 min)"
	@echo "     make gcp_gateway_down      Tear down API Gateway"
	@echo ""
	@echo "   Schema change workflow:"
	@echo "     models/qualtrics.py → bq_schemas.py → web_service_payload.json"
	@echo "     → test_models.py → make gcp_infra_down && make gcp_infra_up"
	@echo ""

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

setup: setup_r setup_python
	@echo ""
	@echo "✅ Full setup complete. Run 'make validate' to verify the structure."

setup_r: _check_r_env
	@echo "🔧 Setting up R environment..."
	@echo ""
	@Rscript -e "if (!requireNamespace('renv', quietly=TRUE)) { \
		cat('Installing renv...\n'); \
		install.packages('renv', repos='https://cloud.r-project.org/'); \
	} else { cat('renv already available.\n') }" || { \
		echo "❌ Failed to check/install renv"; \
		exit 1; \
	}
	@echo ""
	@echo "Restoring project packages from renv.lock (this may take a while)..."
	@cd "$(ROOT)" && Rscript -e "renv::restore()" || { \
		echo ""; \
		echo "❌ renv::restore() failed."; \
		echo "   Try: make renv_repair"; \
		exit 1; \
	}
	@echo ""
	@echo "✅ R environment ready."

setup_python:
	@command -v poetry >/dev/null 2>&1 || { \
		echo "❌ Poetry not found."; \
		echo "   Install: https://python-poetry.org/docs/#installation"; \
		exit 1; \
	}
	@echo "📦 Installing Python dependencies..."
	@cd "$(ROOT)" && poetry install \
		--with fn-qualtrics-scheduling,fn-intake-confirmation,fn-followup-scheduling,dev || { \
		echo "❌ poetry install failed"; \
		exit 1; \
	}
	@echo "✅ Python environment ready."

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------

validate:
	@echo "✅ Running static structure validation (no packages needed)..."
	@echo ""
	@cd "$(ROOT)/analysis/tests" && bash validate_r_structure.sh || { \
		echo ""; \
		echo "❌ Validation failed. Fix reported issues before running analyses."; \
		exit 1; \
	}

# ---------------------------------------------------------------------------
# R Environment
# ---------------------------------------------------------------------------

renv_restore: _check_r_env
	@echo "🧰 Restoring R environment from renv.lock..."
	@echo ""
	@cd "$(ROOT)" && Rscript -e "renv::restore()" || { \
		echo ""; \
		echo "❌ renv::restore() failed."; \
		echo "   Possible causes:"; \
		echo "   • Network issue downloading packages"; \
		echo "   • renv cache corruption → try: make renv_repair"; \
		echo "   • renv not installed   → try: make setup_r"; \
		exit 1; \
	}
	@echo ""
	@echo "✅ R environment restored."

renv_status: _check_r_env
	@echo "👨🏾‍⚕️ Checking renv status..."
	@echo ""
	@cd "$(ROOT)" && Rscript -e "renv::status()" || { \
		echo "❌ renv::status() failed — environment may be incomplete."; \
		echo "   Run: make renv_restore"; \
		exit 1; \
	}

renv_repair: _check_r_env
	@echo "🛠️  Repairing broken renv cache and symlinks..."
	@echo ""
	@cd "$(ROOT)" && Rscript -e "renv::repair()" || { \
		echo "⚠️  renv::repair() encountered errors — continuing to restore..."; \
	}
	@echo ""
	@echo "Re-restoring packages after repair..."
	@cd "$(ROOT)" && Rscript -e "renv::restore()" || { \
		echo ""; \
		echo "❌ Restore after repair failed."; \
		echo "   Last resort: delete renv/library/ and run 'make renv_restore'"; \
		exit 1; \
	}
	@echo ""
	@echo "✅ Repair complete. Verify with: make renv_status"

renv_snapshot: _check_r_env
	@echo "📸 Snapshotting R environment to renv.lock..."
	@echo ""
	@cd "$(ROOT)" && Rscript -e "renv::snapshot()" || { \
		echo "❌ renv::snapshot() failed."; \
		exit 1; \
	}
	@echo ""
	@echo "✅ renv.lock updated. Review changes with: git diff renv.lock"

# ---------------------------------------------------------------------------
# Power Analysis
# ---------------------------------------------------------------------------

power_analysis_dev: _check_r_env validate
	@echo "👨🏾‍💻 Running power analysis (dev grid) — foreground, logs to terminal + file..."
	@echo ""
	@bash "$(ROOT)/analysis/run_power_analysis/main.sh" dev || { \
		echo ""; \
		echo "❌ Power analysis (dev) failed. Check logs in:"; \
		echo "   analysis/run_power_analysis/logs/"; \
		exit 1; \
	}
	@echo ""
	@echo "✅ Power analysis (dev) complete."

power_analysis_prod: _check_r_env validate
	@echo "👨🏾‍💻 Starting power analysis (full grid, set 2) in background..."
	@echo ""
	@echo "⚠️  This takes hours. Do NOT run from a worktree — output paths may collide."
	@echo ""
	@nohup bash "$(ROOT)/analysis/run_power_analysis/main.sh" prod \
		> "$(ROOT)/analysis/run_power_analysis/logs/prod_$$(date +%Y%m%d_%H%M%S).log" 2>&1 & \
	echo "🚀 Power analysis (set 2) started with PID: $$!"; \
	echo "   Monitor: tail -f analysis/run_power_analysis/logs/*.log"

power_analysis_prod_set1: _check_r_env validate
	@echo "👨🏾‍💻 Starting power analysis (full grid, set 1) in background..."
	@echo ""
	@echo "⚠️  This takes hours. Do NOT run from a worktree — output paths may collide."
	@echo ""
	@nohup bash "$(ROOT)/analysis/run_power_analysis/main.sh" prod_set1 \
		> "$(ROOT)/analysis/run_power_analysis/logs/prod_set1_$$(date +%Y%m%d_%H%M%S).log" 2>&1 & \
	echo "🚀 Power analysis (set 1) started with PID: $$!"; \
	echo "   Monitor: tail -f analysis/run_power_analysis/logs/*.log"

# ---------------------------------------------------------------------------
# Synthetic Data Analysis
# ---------------------------------------------------------------------------

synthetic_eda: _check_r_env _check_synthetic_inputs
	@echo "📊 Running EDA script..."
	@Rscript "$(ROOT)/analysis/run_synthetic_data/scripts/r/eda.R" || { \
		echo "❌ eda.R failed"; \
		exit 1; \
	}
	@echo "✅ EDA complete. Figures → analysis/run_synthetic_data/figs/eda/"

synthetic_measurement: _check_r_env _check_synthetic_inputs
	@echo "📐 Running measurement model..."
	@Rscript "$(ROOT)/analysis/run_synthetic_data/scripts/r/measurement_model.R" || { \
		echo "❌ measurement_model.R failed"; \
		exit 1; \
	}
	@echo "✅ Measurement model complete."

synthetic_mlm: _check_r_env _check_synthetic_inputs
	@echo "📈 Running multilevel model (main analysis)..."
	@Rscript "$(ROOT)/analysis/run_synthetic_data/scripts/r/multilevel_model.R" || { \
		echo "❌ multilevel_model.R failed"; \
		exit 1; \
	}
	@echo "✅ MLM complete. Figures → analysis/run_synthetic_data/figs/mlm/"

synthetic_correlation: _check_r_env _check_synthetic_inputs
	@echo "🔗 Running correlation analysis..."
	@Rscript "$(ROOT)/analysis/run_synthetic_data/scripts/r/correlation.R" || { \
		echo "❌ correlation.R failed"; \
		exit 1; \
	}
	@echo "✅ Correlation analysis complete."

synthetic_analysis: synthetic_eda synthetic_correlation synthetic_measurement synthetic_mlm
	@echo ""
	@echo "✅ All synthetic data analyses complete."

# ---------------------------------------------------------------------------
# Python Dev
# ---------------------------------------------------------------------------

py_install:
	@echo "📦 Installing all Python dependency groups..."
	@cd "$(ROOT)" && poetry install \
		--with fn-qualtrics-scheduling,fn-intake-confirmation,fn-followup-scheduling,dev
	@echo "✅ Python dependencies installed."

py_lint:
	@echo "🔍 Running ruff check..."
	@cd "$(ROOT)" && poetry run ruff check . && echo "✅ ruff check passed"
	@echo ""
	@echo "🔍 Checking ruff format..."
	@cd "$(ROOT)" && poetry run ruff format --check . && echo "✅ ruff format check passed"

py_format:
	@echo "✨ Auto-formatting with ruff..."
	@cd "$(ROOT)" && poetry run ruff check --fix . && poetry run ruff format .
	@echo "✅ Formatting complete."

py_sqlfmt:
	@echo "🗄️  Running sqlfmt check..."
	@cd "$(ROOT)" && poetry run sqlfmt --check . && echo "✅ sqlfmt passed"

py_test:
	@echo "🧪 Running Python tests..."
	@cd "$(ROOT)" && poetry run pytest gcp/tests/ -v

# ---------------------------------------------------------------------------
# GCP
# ---------------------------------------------------------------------------

gcp_dev:
	@echo "🖥️  Starting local dev server for: $(FN)"
	@echo "   (Override with: make gcp_dev FN=run_intake_confirmation)"
	@echo ""
	@cd "$(ROOT)" && python gcp/deploy/manage_functions.py dev $(FN)

gcp_deploy:
	@echo "🚀 Deploying $(FN) to GCP..."
	@echo ""
	@echo "⚠️  Current branch: $$(git -C "$(ROOT)" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
	@echo "   Deploy from main only — never from a worktree."
	@echo ""
	@cd "$(ROOT)" && python gcp/deploy/manage_functions.py deploy $(FN)

gcp_infra_up:
	@echo "🏗️  Setting up BigQuery tables..."
	@cd "$(ROOT)" && python gcp/deploy/manage_infra.py setup

gcp_infra_down:
	@echo "🗑️  Tearing down BigQuery tables..."
	@cd "$(ROOT)" && python gcp/deploy/manage_infra.py teardown

gcp_gateway_up:
	@echo "🌐 Setting up API Gateway..."
	@cd "$(ROOT)" && python gcp/deploy/manage_gateway.py setup

gcp_gateway_test:
	@echo "🧪 Running end-to-end gateway test..."
	@if [ "$(NOW)" = "1" ]; then \
		echo "   Mode: now+16/32/48 min (--now)"; \
		cd "$(ROOT)" && python gcp/deploy/manage_gateway.py test --now; \
	else \
		echo "   Mode: fixed survey times  (use NOW=1 for rapid scheduling)"; \
		cd "$(ROOT)" && python gcp/deploy/manage_gateway.py test; \
	fi

gcp_gateway_down:
	@echo "🗑️  Tearing down API Gateway..."
	@cd "$(ROOT)" && python gcp/deploy/manage_gateway.py teardown

gcp_pubsub_up:
	@echo "📨 Setting up Pub/Sub topics..."
	@cd "$(ROOT)" && python gcp/deploy/manage_pubsub.py setup

gcp_pubsub_down:
	@echo "🗑️  Tearing down Pub/Sub topics..."
	@cd "$(ROOT)" && python gcp/deploy/manage_pubsub.py teardown

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

status:
	@echo "🔍 Project Status"
	@echo ""
	@echo "📋 Metadata:"
	@echo "   Version : $(VERSION)"
	@echo "   Author  : $(AUTHOR)"
	@echo ""
	@echo "📁 File counts:"
	@echo "   R scripts    : $$(find "$(ROOT)/analysis" -name '*.r' -o -name '*.R' 2>/dev/null | wc -l | tr -d ' ') found"
	@echo "   YAML configs : $$(find "$(ROOT)/analysis" -name '*.yaml' 2>/dev/null | wc -l | tr -d ' ') found"
	@echo "   CSV data     : $$(find "$(ROOT)/analysis" -name '*.csv' 2>/dev/null | wc -l | tr -d ' ') found"
	@echo "   Python files : $$(find "$(ROOT)/gcp" -name '*.py' 2>/dev/null | wc -l | tr -d ' ') found"
	@echo ""
	@echo "🔒 Lock files:"
	@if [ -f "$(ROOT)/renv.lock" ]; then \
		echo "   renv.lock    ✅  ($$(wc -l < "$(ROOT)/renv.lock" | tr -d ' ') lines)"; \
	else \
		echo "   renv.lock    ❌  MISSING"; \
	fi
	@if [ -f "$(ROOT)/poetry.lock" ]; then \
		echo "   poetry.lock  ✅"; \
	else \
		echo "   poetry.lock  ❌  MISSING"; \
	fi
	@echo ""
	@echo "🌿 Git:"
	@echo "   Branch : $$(git -C "$(ROOT)" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'not a git repo')"

clean:
	@echo "🧹 Cleaning temporary files..."
	@find "$(ROOT)" -name "*.tmp" -delete 2>/dev/null || true
	@find "$(ROOT)" -name ".Rhistory" -delete 2>/dev/null || true
	@find "$(ROOT)" -name "Rplots.pdf" -delete 2>/dev/null || true
	@echo "✅ Cleanup complete."

welcome:
ifndef NAME
	@echo "🚨 Name required!"
	@echo "   Usage: make welcome NAME=\"Your Name\""
else
	@echo ""
	@echo "Hola buenas, $(NAME)! Encantado conocerte 😉"
	@echo ""
	@echo "Welcome to my doctoral thesis research project:"
	@echo "$(PROJECT_NAME)"
	@echo ""
	@echo "Version: $(VERSION)   |   Author: $(AUTHOR)"
	@echo ""
	@echo "📁 Project structure:"
	@echo "   analysis/run_power_analysis/    MLM power simulations (R)"
	@echo "   analysis/run_synthetic_data/    Synthetic ESM data analysis (R)"
	@echo "   gcp/                            Cloud Run data collection pipeline (Python)"
	@echo "   renv.lock                       R package snapshot"
	@echo "   pyproject.toml                  Python Poetry config"
	@echo ""
	@echo "🚀 Quick start for replicators:"
	@echo "   make setup                      Set up R + Python environments"
	@echo "   make validate                   Pre-flight structure check"
	@echo "   make power_analysis_dev         Run power analysis (dev grid)"
	@echo "   make synthetic_analysis         Run all synthetic data analyses"
	@echo "   make help                       Full command reference"
	@echo ""
	@echo "Ready to get started, $(NAME)! 🎯"
endif
