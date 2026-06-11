#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# setup_gcp_vm.sh - Bootstrap R environment on a fresh GCP Ubuntu VM
#
# 1. Installs R via CRAN PPA + full system deps for source compilation
# 2. Installs uvr binary to /usr/local/bin (available in non-interactive shells)
# 3. Patches uvr.lock / uvr.toml to match the installed R version, preventing
#    the library-wipe loop that occurs when the PPA installs a newer R than
#    the dev machine pin in uvr.lock
# 4. Pre-installs Matrix via Rscript to avoid the uvr pipe-deadlock on
#    SuiteSparse compilation (64 KB pipe buffer overflow)
# 5. Delegates to `make setup_r` for the remaining uvr sync
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
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
	|| fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
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
	libcurl4-openssl-dev libssl-dev libxml2-dev \
	cmake \
	libcairo2-dev libfontconfig1-dev libfreetype6-dev \
	libfribidi-dev libharfbuzz-dev \
	libtiff-dev libwebp-dev libx11-dev \
	libuv1-dev libnode-dev \
	pandoc

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

# ---- Install uvr -------------------------------------------------------------
# uvr is a Rust-based R package manager. The binary must land in /usr/local/bin
# so it is available in non-interactive SSH sessions (which skip ~/.bashrc and
# therefore never see ~/.local/bin on PATH).

UVR_VERSION="0.2.15"
UVR_URL="https://github.com/nbafrank/uvr/releases/download/v${UVR_VERSION}/uvr-x86_64-unknown-linux-musl.tar.gz"

echo "Installing uvr v${UVR_VERSION}..."
wget -qO /tmp/uvr.tar.gz "${UVR_URL}"
tar -xzf /tmp/uvr.tar.gz -C /tmp
sudo mv /tmp/uvr /usr/local/bin/uvr
sudo chmod +x /usr/local/bin/uvr
rm -f /tmp/uvr.tar.gz
uvr --version

# ---- Patch uvr.lock / uvr.toml for the installed R version -------------------
# The CRAN PPA always installs the latest R 4.x, which may differ from the R
# version pinned in uvr.lock (set on the dev machine). A mismatch causes uvr to
# wipe .uvr/library/ and restart on every sync. Patch both files in-place
# before the first sync. These are VM-local edits only; the lock files are not
# committed (the pre-commit hook blocks that).

r_full_ver=$(Rscript --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
echo "Patching uvr.lock and uvr.toml to R ${r_full_ver}..."

if [ -f "uvr.lock" ]; then
	awk -v ver="${r_full_ver}" '
		/^\[r\]/ { in_r=1 }
		in_r && /^version = / { print "version = \"" ver "\""; in_r=0; next }
		{ print }
	' uvr.lock >uvr.lock.tmp && mv uvr.lock.tmp uvr.lock
	echo "  uvr.lock patched."
fi

if [ -f "uvr.toml" ]; then
	sed -i "s/^r_version = \"[^\"]*\"/r_version = \"${r_full_ver}\"/" uvr.toml
	echo "  uvr.toml patched."
fi

# ---- Pre-install Matrix to avoid pipe-deadlock on uvr sync -------------------
# Matrix compiles SuiteSparse (~500 KB of compiler output). uvr captures
# R CMD INSTALL output through a 64 KB pipe; the child blocks on pipe_write,
# the parent blocks on do_wait -- deadlock. Installing Matrix directly via
# Rscript writes output to a log file, bypassing the pipe entirely.

echo "Pre-installing Matrix (avoids uvr pipe-deadlock on SuiteSparse)..."
Rscript -e 'install.packages("Matrix", repos="https://cloud.r-project.org/", lib=".uvr/library/", Ncpus=4)' \
	>"${TMPDIR:-/tmp}/matrix_install.log" 2>&1 || {
	echo "WARNING: Matrix pre-install failed. See ${TMPDIR:-/tmp}/matrix_install.log"
	cat "${TMPDIR:-/tmp}/matrix_install.log"
}

# ---- Delegate to make setup_r ------------------------------------------------

echo "Restoring R packages via uvr sync..."
make setup_r

echo ""
echo "[$(date '+%Y-%m-%d %H:%M:%S')] GCP VM setup complete."
echo "  Next: make power_analysis_gcp_benchmark"
