#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# clean_linux_distro.sh - Idempotent pre-flight cleanup for university Linux VMs
#
# Frees /boot space, repairs dpkg state, and verifies apt is functional.
# Run BEFORE setup_remote.sh on any fresh university VM.
#
# Safe to run on already-clean VMs: exits 0 immediately if no action needed.
#
# Usage (from project root):
#   bash clean_linux_distro.sh
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

# ---------------------------------------------------------------------------
# [1] Disk health check — exit early if VM is already clean
# ---------------------------------------------------------------------------

BOOT_USAGE=$(df /boot --output=pcent 2>/dev/null | tail -1 | tr -d ' %' || echo "0")
DPKG_PENDING=$(dpkg --audit 2>/dev/null | wc -l | tr -d ' ')

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Disk health check:"
df -h / /boot 2>/dev/null

if [[ "${BOOT_USAGE}" -lt 75 ]] && [[ "${DPKG_PENDING}" -eq 0 ]]; then
    echo ""
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ VM is already clean (boot ${BOOT_USAGE}% full, dpkg OK)."
    echo "   Proceed with: bash setup_remote.sh"
    exit 0
fi

echo ""
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Action needed: boot=${BOOT_USAGE}% full, dpkg_pending=${DPKG_PENDING} packages"
echo ""

# ---------------------------------------------------------------------------
# [2] Free /boot space — manual file deletion ONLY (no apt)
#
# apt itself writes to /boot during kernel management. If /boot is full,
# apt fails before doing anything useful. Manual rm is the only bootstrap.
# ---------------------------------------------------------------------------

RUNNING=$(uname -r)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running kernel: ${RUNNING} (will NOT be removed)"
echo ""
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Freeing /boot space..."

# Remove kernel files for all versions except the running kernel
for kver in $(ls /boot/vmlinuz-* 2>/dev/null | sed 's|/boot/vmlinuz-||' | sort -V); do
    if [[ "${kver}" != "${RUNNING}" ]]; then
        echo "   Removing old kernel files for: ${kver}"
        sudo rm -f "/boot/vmlinuz-${kver}"
        sudo rm -f "/boot/config-${kver}"
        sudo rm -f "/boot/System.map-${kver}"
    fi
done

# Remove ALL initrd images — dpkg --configure -a will regenerate for the running kernel
# initrd files are the largest consumers (~50-60 MB each); regeneration needs free space
for f in /boot/initrd.img-*; do
    [[ -e "${f}" ]] && sudo rm -f "${f}" && echo "   Removed: ${f}"
done

# Remove stale symlinks
sudo rm -f /boot/vmlinuz.old /boot/initrd.img.old

echo ""
echo "[$(date '+%Y-%m-%d %H:%M:%S')] /boot after manual cleanup:"
df -h /boot

# ---------------------------------------------------------------------------
# [3] Fix broken dpkg state
#
# This regenerates the initrd for the running kernel. Now possible because
# /boot has space. Idempotent: no-op if nothing is pending.
# ---------------------------------------------------------------------------

echo ""
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running dpkg --configure -a (may regenerate initrd)..."
sudo dpkg --configure -a

# ---------------------------------------------------------------------------
# [4] apt cleanup
# ---------------------------------------------------------------------------

echo ""
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running apt cleanup..."
sudo apt-get autoremove --purge -y
sudo apt-get clean
sudo apt-get update -qq

# ---------------------------------------------------------------------------
# [5] Final health report
# ---------------------------------------------------------------------------

echo ""
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Final disk health:"
df -h / /boot 2>/dev/null

ROOT_AVAIL_KB=$(df / --output=avail 2>/dev/null | tail -1 | tr -d ' ')
if [[ "${ROOT_AVAIL_KB}" -lt 3145728 ]]; then
    echo ""
    echo "⚠️  Warning: root filesystem has less than 3 GB free (${ROOT_AVAIL_KB} KB)."
    echo "   renv::restore() needs ~1-2 GB for the package cache."
fi

DPKG_REMAINING=$(dpkg --audit 2>/dev/null | wc -l | tr -d ' ')
if [[ "${DPKG_REMAINING}" -gt 0 ]]; then
    echo ""
    echo "❌ dpkg still has ${DPKG_REMAINING} unconfigured package(s). Manual intervention needed."
    echo "   Try: sudo dpkg --configure -a"
    exit 1
fi

echo ""
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ VM cleanup complete."
echo ""
echo "Next step: bash setup_remote.sh"
