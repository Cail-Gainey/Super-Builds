#!/bin/bash
set -euo pipefail

# Optional feature patches from the kernel_patches artifact.
#
# Unlike apply-kernel-patches.sh (which tolerates failures with `|| true`
# because a missing micro-optimisation is harmless), these add whole features
# that the defconfig then switches on. A silently skipped patch would leave
# CONFIG_TCP_CONG_BBR3 / CONFIG_NTSYNC referencing Kconfig symbols that do not
# exist, so every failure here is fatal.
#
# Source: https://github.com/WildKernels/kernel_patches/tree/main/common

KERNEL_DIR="${1:?Usage: setup-extra-features.sh <kernel_dir> <android_ver> <kernel_ver> <patches_dir>}"
ANDROID_VER="${2:?}"
KERNEL_VER="${3:?}"
PATCHES_DIR="${4:?}"

ADD_BBRV3="${ADD_BBRV3:-false}"
ADD_NTSYNC="${ADD_NTSYNC:-false}"

COMMON="$PATCHES_DIR/common"
cd "$KERNEL_DIR"

# --batch so patch can never prompt or reverse-apply on a non-TTY, --forward so
# an already-applied tree errors instead of being silently undone, no -F so a
# shifted hunk is a failure rather than a guess.
apply_strict() {
  local patch="$1"
  [ -f "$patch" ] || { echo "FATAL: missing required patch $patch"; exit 1; }
  patch -p1 --batch --forward --no-backup-if-mismatch < "$patch" || {
    echo "FATAL: $(basename "$patch") did not apply cleanly"
    exit 1
  }
}

# Some compat patches ship per-baseline variants (e.g. the lockdep.h layout
# differs across android12-5.10 sublevels). Probe them and use the one that fits.
apply_first_match() {
  local candidate
  for candidate in "$@"; do
    [ -f "$candidate" ] || continue
    if patch -p1 --batch --forward --dry-run < "$candidate" >/dev/null 2>&1; then
      apply_strict "$candidate"
      echo "  variant: $(basename "$candidate")"
      return 0
    fi
  done
  echo "FATAL: none of these variants apply: $*"
  exit 1
}

if [ "$ADD_BBRV3" = "true" ]; then
  BBR="$COMMON/bbrv3"
  # BBRv3 sysctls need proc_dou8vec_minmax, which newer sublevels already carry.
  # Only backport it when it is genuinely absent.
  if ! grep -rq "proc_dou8vec_minmax" include/linux/sysctl.h; then
    apply_strict "$BBR/sysctl_add_proc_dou8vec_minmax.patch"
    apply_strict "$BBR/sysctl_fix_data-races_in_proc_dou8vec_minmax.patch"
  else
    echo "setup-extra-features: proc_dou8vec_minmax already present, skipping backport"
  fi
  apply_strict "$BBR/0001-net-tcp-backport-BBRv3-to-${ANDROID_VER}-${KERNEL_VER}.patch"
  echo "setup-extra-features: BBRv3 applied"
fi

if [ "$ADD_NTSYNC" = "true" ]; then
  NT="$COMMON/ntsync"
  apply_strict "$NT/ntsync_base.patch"
  apply_first_match \
    "$NT/ntsync_compat_${ANDROID_VER}-${KERNEL_VER}.patch" \
    "$NT/ntsync_compat_${ANDROID_VER}-${KERNEL_VER}_A14.patch"
  echo "setup-extra-features: NTSync applied"
fi
