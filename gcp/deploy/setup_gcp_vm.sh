#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# setup_gcp_vm.sh - Bootstrap R environment on a fresh GCP Ubuntu VM
#
# Installs R >= 4.4 via CRAN PPA, system libraries for compiling R packages,
# and delegates to `make setup_r` for renv::restore().
#
# Usage: bash gcp/deploy/setup_gcp_vm.sh   (from the project root)
# ---------------------------------------------------------------------------

set -euo pipefail

# ---- Guards ---------------------------------------------------------------

# OS guard: Ubuntu or Debian only
if ! grep -qiE 'ubuntu|debian' /etc/os-release 2>/dev/null; then
    echo "ERROR: This script is designed for Ubuntu/Debian. Detected OS:"
    cat /etc/os-release 2>/dev/null || echo "  (unknown)"
    exit 1
fi

# Project root guard: Makefile must be present
if [ ! -f "Makefile" ]; then
    echo "ERROR: Makefile not found. Run this script from the project root."
    echo "  cd /path/to/dkg-phd-thesis && bash gcp/deploy/setup_gcp_vm.sh"
    exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting GCP VM setup..."

# ---- Wait for dpkg lock --------------------------------------------------
# GCP Ubuntu images may trigger unattended-upgrades on first boot, which
# holds the dpkg lock and causes apt operations to fail.

echo "Checking for dpkg lock..."
max_wait=300
waited=0
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
      fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    if [ $waited -eq 0 ]; then
        echo "  dpkg lock held (likely unattended-upgrades). Waiting up to ${max_wait}s..."
    fi
    sleep 5
    waited=$((waited + 5))
    if [ $waited -ge $max_wait ]; then
        echo "ERROR: dpkg lock held for over ${max_wait}s. Kill the blocking process or wait."
        exit 1
    fi
done
if [ $waited -gt 0 ]; then
    echo "  Lock released after ${waited}s."
else
    echo "  No lock held."
fi

# ---- Install R via CRAN PPA ----------------------------------------------

echo "Installing prerequisites..."
sudo apt-get update -qq
sudo apt-get install -y -qq software-properties-common dirmngr wget

echo "Adding CRAN signing key..."
wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc \
    | sudo tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc >/dev/null

echo "Adding CRAN R 4.x PPA..."
sudo add-apt-repository -y \
    "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/"
sudo apt-get update -qq

echo "Installing R and system build dependencies..."
sudo apt-get install -y -qq \
    r-base r-base-dev build-essential \
    libgfortran5 \
    liblapack-dev libopenblas-dev \
    libcurl4-openssl-dev libssl-dev libxml2-dev

# ---- Verify R version ----------------------------------------------------

echo "Verifying R version..."
r_ver=$(Rscript --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
r_major=$(echo "$r_ver" | cut -d. -f1)
r_minor=$(echo "$r_ver" | cut -d. -f2)

if [ "$r_major" -lt 4 ] || { [ "$r_major" -eq 4 ] && [ "$r_minor" -lt 4 ]; }; then
    echo "ERROR: R >= 4.4 required, got ${r_ver}"
    exit 1
fi
echo "  R version: ${r_ver} (OK)"

# ---- Delegate to make setup_r --------------------------------------------

echo "Restoring R packages via renv..."
make setup_r

echo ""
echo "[$(date '+%Y-%m-%d %H:%M:%S')] GCP VM setup complete."
echo "  Next: make power_analysis_gcp_benchmark"
