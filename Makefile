# Project information
PROJECT_NAME := "If You Only Knew the Power of the Dark Side": Examining Within-Person Fluctuation in Psychological Need Frustration, Burnout, and Turnover Intentions Across a Workday
VERSION := 1.0.0
AUTHOR := Demetrius K. Green, ABD

# Change default to help instead of welcome
.DEFAULT_GOAL := help

# Help - no name required
.PHONY: help
help:
	@echo "=========================================="
	@echo "Available Make Targets"
	@echo "=========================================="
	@echo ""
	@echo "📋 Main Commands:"
	@echo "  welcome NAME=\"Your Name\" - Show personalized welcome message"
	@echo "  help                       - Show this help (default)"
	@echo "  status                     - Show project status"
	@echo "  power_analysis             - Run power analysis pipeline"
	@echo "  clean                      - Clean temporary files"
	@echo ""
	@echo "🔧 R Environment Management:"
	@echo "  renv_restore             - Restore R environment using renv"
	@echo "  renv_snapshot            - Snapshot of R environment"
	@echo "  renv_repair              - Repair broken renv cache and symlinks"
	@echo "  renv_status              - Check renv status"
	@echo ""
	@echo "💡 Examples:"
	@echo "  make welcome NAME=\"Alex Doe\""
	@echo "  make power_analysis VERSION=dev"
	@echo "  make power_analysis VERSION=prod"
	@echo "  make renv_repair"
	@echo ""
	@echo "📚 Project: $(PROJECT_NAME)"
	@echo "👨‍🎓 Author: $(AUTHOR)"

# Welcome message - requires NAME
.PHONY: welcome
welcome:
ifndef NAME
	@echo "🚨 Name required for welcome message!"
	@echo ""
	@echo "Usage: make welcome NAME=\"Your Name\""
	@echo ""
	@echo "Example: make welcome NAME=\"Alex Doe\""
else
	@echo "=========================================="
	@echo "Hola buenas, $(NAME)! Encantado conocerte 😉 Welcome to my doctoral thesis research project:"
	@echo "$(PROJECT_NAME)"
	@echo "Version: $(VERSION)"
	@echo "Author: $(AUTHOR)"
	@echo "=========================================="
	@echo ""
	@echo "📁 Project Structure Overview:"
	@echo "  • R source code in srcR/"
	@echo "  • Power analysis pipeline in srcR/run_power_analysis/"
	@echo "  • Reporting pipeline in srcR/run_power_reporting/"
	@echo "  • Project images in images/"
	@echo ""
	@echo "🚀 Available commands:"
	@echo "  make help           - Show all available targets"
	@echo "  make status         - Show project status"
	@echo "  make renv_restore   - Restore R environment"
	@echo "  make renv_snapshot  - Snapshot of R environment"
	@echo "  make renv_repair    - Repair broken renv cache"
	@echo "  make power_analysis - Run power analysis pipeline"
	@echo "  make clean          - Clean temporary files"
	@echo ""
	@echo "Ready to get started, $(NAME)! 🎯"
endif

# Status - no name required  
.PHONY: status
status:
	@echo "🔍 Project Status Check:"
	@echo "  Project: $(PROJECT_NAME)"
	@echo "  Version: $(VERSION)"
	@echo "  Author: $(AUTHOR)"
	@echo ""
	@echo "📊 File Counts:"
	@echo "  R files: $$(find srcR -name '*.r' 2>/dev/null | wc -l) found"
	@echo "  Config files: $$(find . -name '*.yaml' 2>/dev/null | wc -l) found"
	@echo "  Data files: $$(find . -name '*.csv' 2>/dev/null | wc -l) found"
	@echo ""
	@echo "📁 Directory structure verified ✅"

# Basic renv restore
.PHONY: renv_restore
renv_restore:
	@echo "🧰 Restoring R environment using renv"
	@echo ""
	@if [ -f "./srcR/run_renv_restore.r" ]; then \
		chmod +x ./srcR/run_renv_restore.r; \
		sudo Rscript ./srcR/run_renv_restore.r; \
		echo ""; \
	else \
		echo "❌ Error: run_renv_restore.r not found in srcR/"; \
		exit 1; \
	fi

# Basic renv restore
.PHONY: renv_snapshot
renv_snapshot:
	@echo "📸 Taking snapshot of R environment using renv"
	@echo ""
	@if [ -f "./srcR/run_renv_snapshot.r" ]; then \
		chmod +x ./srcR/run_renv_snapshot.r; \
		Rscript ./srcR/run_renv_snapshot.r && echo "✅ R environment snapshotted using renv."; \
	else \
		echo "❌ Error: run_renv_snapshot.r not found in srcR/"; \
		exit 1; \
	fi

# Enhanced renv repair - fixes cache issues
.PHONY: renv_repair
renv_repair:
	@echo "🛠️ Repairing R environment using renv"
	@echo ""
	@if [ -f "./srcR/run_renv_repair.r" ]; then \
		chmod +x ./srcR/run_renv_repair.r; \
		Rscript ./srcR/run_renv_repair.r && echo "✅ R environment repaired using renv."; \
	else \
		echo "❌ Error: run_renv_repair.r not found"; \
		exit 1; \
	fi

# Check renv status
.PHONY: renv_status
renv_status:
	@echo "👨🏾‍⚕️ Checking renv status..."
	@echo ""
	@if [ -f "./srcR/run_renv_status.r" ]; then \
		chmod +x ./srcR/run_renv_status.r; \
		Rscript ./srcR/run_renv_status.r && echo "✅ R environment status reviewed."; \
	else \
		echo "❌ Error: run_renv_status.r not found"; \
		exit 1; \
	fi

# Power analysis pipeline
.PHONY: power_analysis
power_analysis:
	@echo "👨🏾‍💻 Running Power Analysis Pipeline..."
	@version=$${VERSION:-dev}; \
	echo "Using version: $$version"; \
	echo ""; \
	if [ -f "./srcR/run_power_analysis/run_power_analysis.sh" ]; then \
		chmod +x ./srcR/run_power_analysis/run_power_analysis.sh; \
		cd srcR/run_power_analysis && \
		nohup bash run_power_analysis.sh $$version > logs/run_power_analysis_$$(date +"%Y%m%d_%H%M%S").log 2>&1 & \
		echo "Power analysis started in background with PID: $$!"; \
		echo "Check logs in: srcR/run_power_analysis/logs/"; \
	else \
		echo "❌ Error: run_power_analysis.sh not found!"; \
		exit 1; \
	fi

# Clean - no name required
.PHONY: clean
clean:
	@echo "🧹 Cleaning temporary files..."
	@find . -name "*.tmp" -delete 2>/dev/null || true
	@find . -name ".Rhistory" -delete 2>/dev/null || true
	@find . -name "Rplots.pdf" -delete 2>/dev/null || true
	@echo "✅ Cleanup complete!"
