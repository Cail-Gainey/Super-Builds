#!/bin/bash
set -euo pipefail

# Droidspaces GKI support: kABI-safe patches that let CONFIG_SYSVIPC,
# CONFIG_IPC_NS and CONFIG_POSIX_MQUEUE be enabled without shifting
# task_struct/user_struct offsets, which would otherwise bootloop the device
# once pre-compiled vendor modules load.
#
# These patches are mandatory, not best-effort: enabling the matching configs
# without them bootloops on first boot. Every failure here is fatal so the
# build stops before producing an unbootable image.
#
# Reference: https://github.com/ravindu644/Droidspaces-OSS
#            Documentation/Kernel-Configuration.md#configuring-gki-kernels

KERNEL_DIR="${1:?Usage: setup-droidspaces.sh <kernel_dir> <kernel_ver> <patches_dir>}"
KERNEL_VER="${2:?}"
PATCHES_DIR="${3:?}"

DS="$PATCHES_DIR/common/droidspaces"
[ -d "$DS" ] || { echo "FATAL: droidspaces patches not found at $DS"; exit 1; }

MAJOR="${KERNEL_VER%%.*}"
MINOR="${KERNEL_VER#*.}"

cd "$KERNEL_DIR"

apply_required() {
  local patch="$1"
  [ -f "$patch" ] || { echo "FATAL: missing required patch $patch"; exit 1; }
  # --batch: never prompt. Without it patch reads the answer from the
  #   redirected patch file on a non-TTY and can silently reverse-apply,
  #   undoing the kABI fix while still reporting success.
  # --forward: treat an already-applied/reversed patch as a skip (exit 1)
  #   instead of reversing it.
  # No -F fuzz: a shifted hunk means the kABI slot assumption no longer
  #   holds, which is a bootloop risk.
  patch -p1 --batch --forward --no-backup-if-mismatch < "$patch" || {
    echo "FATAL: $(basename "$patch") did not apply cleanly"
    exit 1
  }
}

# SYSVIPC kABI fix — slot layout differs on 6.12+
if [ "$MAJOR" -gt 6 ] || { [ "$MAJOR" -eq 6 ] && [ "$MINOR" -ge 12 ]; }; then
  apply_required "$DS/fix_sysvipc_kabi_a16-6.12.patch"
else
  apply_required "$DS/fix_sysvipc_kabi_6_7_8.patch"
fi

# POSIX_MQUEUE moves mq_bytes into user_struct KABI padding — 5.10 and below
if [ "$MAJOR" -lt 5 ] || { [ "$MAJOR" -eq 5 ] && [ "$MINOR" -le 10 ]; }; then
  apply_required "$DS/fix_abi_padding_for_posix_mqueue.patch"
fi

# CONFIG_USER_NS is required for rootless/procfs handling but unrestricted
# user namespaces are a local privilege escalation surface on Android.
# Gate creation behind CAP_SYS_ADMIN; root-run containers are unaffected.
apply_required "$DS/0001-Guard-USER_NS-for-non-root-users.patch"

echo "setup-droidspaces: kABI patches applied for kernel $KERNEL_VER"
