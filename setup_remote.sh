#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# setup_remote.sh - Bootstrap R 4.4 and renv on a fresh Ubuntu/Debian VM
#
# Installs R 4.4 from the official CRAN PPA, all system build dependencies
# required by the power analysis R packages, and then delegates R package
# installation to `make setup_r` (renv::restore()).
#
# Prerequisites (must be done manually if apt is currently broken):
#   - /boot partition has enough free space (> 100 MB)
#   - dpkg is in a clean state: sudo dpkg --configure -a
#   - apt is functional: sudo apt update
#   See: analysis/run_power_analysis/README.md → "Linux kernel disk space issues"
#
# Usage (run from project root):
#   bash setup_remote.sh
# ---------------------------------------------------------------------------

set -euo pipefail

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------

if [[ ! -f /etc/os-release ]] || ! grep -qiE "ubuntu|debian" /etc/os-release; then
    echo "❌ This script requires Ubuntu or Debian. Detected OS:"
    cat /etc/os-release 2>/dev/null || echo "(could not read /etc/os-release)"
    exit 1
fi

if [[ ! -f "$(dirname "$0")/Makefile" ]]; then
    echo "❌ Run this script from the project root (where the Makefile lives)."
    echo "   cd /path/to/dkg-phd-thesis && bash setup_remote.sh"
    exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting remote VM setup..."
echo ""

# ---------------------------------------------------------------------------
# Step 1: apt prerequisites for adding the CRAN PPA
# ---------------------------------------------------------------------------

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installing apt prerequisites..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    software-properties-common \
    dirmngr \
    wget \
    git

# ---------------------------------------------------------------------------
# Step 2: CRAN signing key
# ---------------------------------------------------------------------------

echo ""
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Adding CRAN signing key..."
wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc \
    | sudo tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc > /dev/null

# ---------------------------------------------------------------------------
# Step 3: CRAN R 4.x PPA (provides the latest R 4.x, currently 4.4.x)
# ---------------------------------------------------------------------------

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Adding CRAN R 4.x repository..."
sudo add-apt-repository -y \
    "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/"

sudo apt-get update -qq

# ---------------------------------------------------------------------------
# Step 4: R 4.4 + system build dependencies
# ---------------------------------------------------------------------------

echo ""
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installing R 4.4 and system build dependencies..."
sudo apt-get install -y --no-install-recommends \
    r-base \
    r-base-dev \
    build-essential \
    libgfortran5 \
    liblapack-dev \
    libopenblas-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev

# ---------------------------------------------------------------------------
# Step 5: Verify R version is 4.4.x
# ---------------------------------------------------------------------------

echo ""
r_ver=$(Rscript --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Installed R version: ${r_ver}"

r_major_minor=$(echo "${r_ver}" | grep -oE '^[0-9]+\.[0-9]+')
if [[ "${r_major_minor}" != "4.4" ]]; then
    echo ""
    echo "❌ Expected R 4.4.x but got ${r_ver}."
    echo "   The CRAN PPA may not have refreshed, or the system R is shadowing the new install."
    echo "   Try: sudo apt-get install --only-upgrade r-base r-base-dev"
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 6: Delegate R package installation to make setup_r
# ---------------------------------------------------------------------------

echo ""
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running make setup_r (installs renv and restores packages)..."
echo "   This may take 10-30 minutes on first run."
echo ""

make setup_r

echo ""
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Remote setup complete."
echo ""
echo "Next steps:"
echo "  make validate                  # pre-flight structure check"
echo "  make power_analysis_dev        # smoke test (~seconds)"
echo "  make power_analysis_prod_set1  # production set 1, background"
echo "  make power_analysis_prod       # production set 2, background"
