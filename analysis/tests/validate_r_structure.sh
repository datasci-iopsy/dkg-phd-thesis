#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# validate_structure.sh - Phase 1 static validation for run_power_analysis
#
# Run from the project root directory (where renv.lock lives).
# Checks directory structure, file presence, path resolution logic,
# and R syntax without requiring any R packages to be installed.
#
# Usage: bash analysis/run_power_analysis/validate_structure.sh
# ---------------------------------------------------------------------------

set -euo pipefail

cd ../../ # Ensure we're at the project root for consistent path checks

pass_count=0
fail_count=0
warn_count=0

pass() {
    echo "  [PASS] $1"
    pass_count=$((pass_count + 1))
}

fail() {
    echo "  [FAIL] $1"
    fail_count=$((fail_count + 1))
}

warn() {
    echo "  [WARN] $1"
    warn_count=$((warn_count + 1))
}

echo ""
echo "======================================================================"
echo "Phase 1: Static Validation for run_power_analysis"
echo "======================================================================"
echo ""

# ---- 1. Project root checks ----
echo "1. Project root checks"
echo "----------------------------------------------------------------------"

if [ -f "renv.lock" ]; then
    pass "renv.lock found at project root"
else
    fail "renv.lock NOT found -- are you running from the project root?"
fi

if [ -f ".Rprofile" ]; then
    pass ".Rprofile found at project root"
else
    warn ".Rprofile NOT found -- renv may not auto-activate"
fi

if [ -f "pyproject.toml" ]; then
    pass "pyproject.toml found (Poetry coexistence confirmed)"
else
    warn "pyproject.toml NOT found at project root"
fi

echo ""

# ---- 2. Directory structure ----
echo "2. Directory structure"
echo "----------------------------------------------------------------------"

expected_dirs=(
    "analysis"
    "analysis/shared"
    "analysis/shared/utils"
    "analysis/run_power_analysis"
    "analysis/run_power_analysis/configs"
    "analysis/run_power_analysis/scripts"
    "analysis/run_power_analysis/utils"
)

for dir in "${expected_dirs[@]}"; do
    if [ -d "${dir}" ]; then
        pass "Directory exists: ${dir}"
    else
        fail "Directory MISSING: ${dir}"
    fi
done

# Runtime directories (not required to exist yet, but note their status)
runtime_dirs=(
    "analysis/run_power_analysis/data"
    "analysis/run_power_analysis/logs"
    # "analysis/run_power_analysis/figs"
)

for dir in "${runtime_dirs[@]}"; do
    if [ -d "${dir}" ]; then
        pass "Runtime directory exists: ${dir} (will be created at runtime if missing)"
    else
        warn "Runtime directory absent: ${dir} (will be created at runtime)"
    fi
done

echo ""

# ---- 3. Required source files ----
echo "3. Required source files"
echo "----------------------------------------------------------------------"

required_files=(
    "analysis/run_power_analysis/main.sh"
    "analysis/run_power_analysis/scripts/run_power_analysis.r"
    "analysis/run_power_analysis/utils/power_analysis_utils.r"
    "analysis/run_power_analysis/configs/run_power_analysis.dev.yaml"
    "analysis/run_power_analysis/configs/run_power_analysis.prod.yaml"
    "analysis/shared/utils/common_utils.r"
)

for f in "${required_files[@]}"; do
    if [ -f "${f}" ]; then
        pass "File exists: ${f}"
    else
        fail "File MISSING: ${f}"
    fi
done

echo ""

# ---- 4. main.sh checks ----
echo "4. main.sh checks"
echo "----------------------------------------------------------------------"

main_sh="analysis/run_power_analysis/main.sh"
if [ -f "${main_sh}" ]; then
    if head -1 "${main_sh}" | grep -q "#!/usr/bin/env bash"; then
        pass "main.sh has correct shebang"
    else
        fail "main.sh shebang is not #!/usr/bin/env bash"
    fi

    if grep -q "set -euo pipefail" "${main_sh}"; then
        pass "main.sh uses strict mode (set -euo pipefail)"
    else
        warn "main.sh does not use strict mode"
    fi

    if grep -q '\-\-version' "${main_sh}"; then
        pass "main.sh passes --version to Rscript"
    else
        fail "main.sh does not pass --version flag to Rscript"
    fi

    if grep -q 'scripts/run_power_analysis.r' "${main_sh}"; then
        pass "main.sh references correct R script path"
    else
        fail "main.sh does not reference scripts/run_power_analysis.r"
    fi
else
    fail "Cannot check main.sh -- file missing"
fi

echo ""

# ---- 5. Path resolution alignment ----
echo "5. Path resolution alignment"
echo "----------------------------------------------------------------------"

# Simulate what resolve_paths() in R would compute
r_script="analysis/run_power_analysis/scripts/run_power_analysis.r"
if [ -f "${r_script}" ]; then
    scripts_dir="$(dirname "${r_script}")"
    program_dir="$(dirname "${scripts_dir}")"
    analysis_dir="$(dirname "${program_dir}")"

    echo "  Simulated resolve_paths() output:"
    echo "    script       -> ${r_script}"
    echo "    scripts_dir  -> ${scripts_dir}"
    echo "    program_dir  -> ${program_dir}"
    echo "    analysis_dir -> ${analysis_dir}"

    # Check that derived paths point to real files
    derived_common="${analysis_dir}/shared/utils/common_utils.r"
    derived_config_dev="${program_dir}/configs/run_power_analysis.dev.yaml"
    derived_config_prod="${program_dir}/configs/run_power_analysis.prod.yaml"
    derived_utils="${program_dir}/utils/power_analysis_utils.r"

    if [ -f "${derived_common}" ]; then
        pass "Derived common_utils path resolves: ${derived_common}"
    else
        fail "Derived common_utils path does NOT resolve: ${derived_common}"
    fi

    if [ -f "${derived_config_dev}" ]; then
        pass "Derived dev config path resolves: ${derived_config_dev}"
    else
        fail "Derived dev config path does NOT resolve: ${derived_config_dev}"
    fi

    if [ -f "${derived_config_prod}" ]; then
        pass "Derived prod config path resolves: ${derived_config_prod}"
    else
        fail "Derived prod config path does NOT resolve: ${derived_config_prod}"
    fi

    if [ -f "${derived_utils}" ]; then
        pass "Derived power_analysis_utils path resolves: ${derived_utils}"
    else
        fail "Derived power_analysis_utils path does NOT resolve: ${derived_utils}"
    fi
else
    fail "Cannot simulate path resolution -- R script missing"
fi

echo ""

# ---- 6. R syntax check ----
echo "6. R syntax check (requires R to be installed)"
echo "----------------------------------------------------------------------"

if command -v Rscript &> /dev/null; then
    r_files=(
        "analysis/shared/utils/common_utils.r"
        "analysis/run_power_analysis/utils/power_analysis_utils.r"
        "analysis/run_power_analysis/scripts/run_power_analysis.r"
    )

    for f in "${r_files[@]}"; do
        if [ -f "${f}" ]; then
            # parse() checks syntax without executing
            if Rscript -e "tryCatch(parse(file='${f}'), error=function(e) quit(status=1))" 2>/dev/null; then
                pass "R syntax valid: ${f}"
            else
                fail "R syntax ERROR: ${f}"
            fi
        fi
    done
else
    warn "Rscript not found -- skipping syntax checks"
    warn "Install R to enable syntax validation"
fi

echo ""

# ---- 7. Content checks ----
echo "7. Content checks (no emoji, no special characters in code)"
echo "----------------------------------------------------------------------"

code_files=(
    "analysis/shared/utils/common_utils.r"
    "analysis/run_power_analysis/utils/power_analysis_utils.r"
    "analysis/run_power_analysis/scripts/run_power_analysis.r"
    "analysis/run_power_analysis/main.sh"
)

for f in "${code_files[@]}"; do
    if [ -f "${f}" ]; then
        # Check for common emoji/special unicode (multi-byte sequences)
        if LC_ALL=C grep -Pn '[\x{1F300}-\x{1FFFF}]|[\x{2600}-\x{27BF}]|[\x{FE00}-\x{FE0F}]|[\x{E0100}-\x{E01EF}]' "${f}" 2>/dev/null; then
            fail "Emoji/special characters found in: ${f} (see lines above)"
        else
            # Fallback: check for specific known emoji bytes
            if grep -Pn '\xF0\x9F|\xe2\x9c\x85|\xf0\x9f\x94\x8d|\xf0\x9f\x93\x9a' "${f}" 2>/dev/null; then
                fail "Emoji bytes detected in: ${f}"
            else
                pass "No emoji/special characters: ${f}"
            fi
        fi
    fi
done

echo ""

# ---- Summary ----
echo "======================================================================"
echo "Phase 1 Summary"
echo "======================================================================"
echo "  Passed:   ${pass_count}"
echo "  Failed:   ${fail_count}"
echo "  Warnings: ${warn_count}"
echo ""

if [ ${fail_count} -eq 0 ]; then
    echo "  Status: READY for Phase 2 (dry-run validation)"
    echo ""
    echo "  Next step: run the dev version from the project root:"
    echo "    cd <project-root>"
    echo "    bash analysis/run_power_analysis/main.sh dev"
    echo ""
else
    echo "  Status: ISSUES FOUND -- resolve failures before proceeding"
    echo ""
fi

exit ${fail_count}
