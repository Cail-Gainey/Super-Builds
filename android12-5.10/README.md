# Kernel Build Directory

Patches, configuration, and build scripts for one GKI kernel version. CI applies these to Google's stock kernel source, compiles across all supported sublevels, and outputs flashable boot images with SUSFS hiding + ZeroMount VFS injection.

See the [root README](../README.md) for project overview and feature details.

---

## Directory Layout

```
├── SukiSU-Ultra/patches/
│   ├── 50_add_susfs_in_gki-*.patch      # upstream SUSFS
│   ├── 51_enhanced_susfs-*.patch         # our enhancements
│   ├── 60_zeromount-*.patch              # ZeroMount VFS driver
│   └── 70_ksu_safety-sukisu-*.patch      # variant-specific fixes
├── ReSukiSU/patches/                     # same 50_/51_/60_, different 70_
├── KernelSU-Next/patches/                # same 50_/51_/60_, different 70_
├── WildKSU/patches/                      # same 50_/51_/60_, different 70_
├── build-helpers/                        # sublevel compat scripts
├── defconfig.fragment                    # kernel config toggles
├── sukisu-pin.txt                        # git commit pin for SukiSU fork
├── resukisu-pin.txt                      # git commit pin for ReSukiSU fork
├── kernelsu-next-pin.txt                 # git commit pin for KSU-Next fork
└── wksu-pin.txt                          # git commit pin for WildKSU fork
```

> **android12-5.4 only has SukiSU and ReSukiSU.** KSU-Next and WildKSU lack pre-5.7 kernel compatibility.

---

## Patches

Four patches per variant. Within the same kernel version, **50_, 51_, and 60_ are identical across all variants.** Only 70_ differs — it targets each KSU fork's specific codebase.

| Patch | Contents | Scope |
|-------|----------|-------|
| **50_** | Upstream SUSFS from [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu). Hooks readdir, namei, stat, proc, namespace, mount. Creates `fs/susfs.c` and supporting headers. | Shared |
| **51_** | Our enhancements on top of upstream: Kconfig-toggled features, bug fixes, hardening, strncpy null-termination, EACCES→ENOENT fix, AS_FLAGS collision guards. | Shared |
| **60_** | ZeroMount VFS driver. Path redirection via `getname()`, directory entry injection, d_path spoofing, xattr injection, statfs spoofing, bloom filter, ioctl interface. | Shared |
| **70_** | KSU fork safety fixes. Null-termination, UID range corrections, zygote SID guards, supercall wiring. Small (~18 lines for SukiSU builtin, larger for others). | Per-variant |

### Application Order

```
50_ → 51_ → 70_ → 60_ → fix-susfs-compat.sh (runtime)
```

50_ lays the SUSFS foundation. 51_ enhances it. 70_ fixes the KSU fork. 60_ adds ZeroMount on top. `fix-susfs-compat.sh` handles sublevel-specific issues that static patches can't cover.

---

## defconfig.fragment

This file gets merged on top of the stock GKI defconfig at build time. Each section controls a feature group. Edit it to enable or disable features for your build.

### [base]

| Toggle | Default | Purpose |
|--------|---------|---------|
| `CONFIG_KSU` | y | KernelSU root framework. Everything depends on this. |
| `CONFIG_UAPI_HEADER_TEST` | n | **5.4 only.** Disables header test that fails with prebuilt clang. Absent on 5.10+. |
| `CONFIG_TCP_CONG_BBR` | y | BBR congestion control. Better throughput on lossy networks. |
| `CONFIG_TCP_CONG_CUBIC` | y | CUBIC congestion control. Linux default. |
| `CONFIG_TCP_CONG_WESTWOOD` | y | Westwood+ congestion control. Good for wireless. |
| `CONFIG_IP_SET` + related | y | ipset support for firewall apps (AFWall+, NetGuard). |
| `CONFIG_KALLSYMS_ALL` | y | Full kernel symbol table. Required by KSU for hook resolution. |

### [susfs]

Every toggle here depends on `CONFIG_KSU_SUSFS=y`. Disable the master toggle and none of these compile.

| Toggle | Default | What it hides |
|--------|---------|---------------|
| `CONFIG_KSU_SUSFS` | y | **Master toggle.** Enables the entire SUSFS hiding framework. |
| `CONFIG_KSU_SUSFS_SUS_PATH` | y | Files and directories vanish from `readdir` and path lookups. Set to `n` on 6.12 (AS_FLAGS bit collision). Absent on 6.6. |
| `CONFIG_KSU_SUSFS_SUS_MOUNT` | y | Mount entries filtered from `/proc/PID/mountinfo`. |
| `CONFIG_KSU_SUSFS_SUS_KSTAT` | y | `stat()`/`fstat()`/`lstat()` return spoofed metadata (inode, device, timestamps). |
| `CONFIG_KSU_SUSFS_SUS_KSTAT_REDIRECT` | y | Maps virtual-path stat to real-file metadata. Used by ZeroMount. |
| `CONFIG_KSU_SUSFS_SUS_MAP` | y | `/proc/PID/maps` and `/proc/PID/mem` entries hidden for flagged inodes. |
| `CONFIG_KSU_SUSFS_SPOOF_UNAME` | y | `uname -r` returns a stock-looking kernel version string. |
| `CONFIG_KSU_SUSFS_ENABLE_LOG` | y | SUSFS debug logging to dmesg. Disable for production if log noise matters. |
| `CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG` | y | `/proc/cmdline` and `/proc/bootconfig` show clean boot state. |
| `CONFIG_KSU_SUSFS_OPEN_REDIRECT` | y | File open operations redirected to alternate paths. |
| `CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS` | y | SUSFS and ZeroMount symbols hidden from `/proc/kallsyms`. |
| `CONFIG_KSU_SUSFS_UNICODE_FILTER` | y | Blocks invisible/confusable unicode characters in filesystem paths. |
| `CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT` | y | Auto-adds KSU default mounts to the hidden mount list. |
| `CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT` | y | Auto-adds bind mounts to the hidden mount list. |
| `CONFIG_KSU_SUSFS_HIDDEN_NAME` | y | Hidden name/inode hash tables + VFS hooks. **5.10 only.** |
| `CONFIG_KSU_SUSFS_HARDENED` | y | Additional hardening checks. **5.10 only.** |

### [zram]

Compressed RAM swap. All compression algorithms enabled so the kernel picks the best one at runtime. Default compressor is LZ4KD. Safe to leave as-is.

### [overlayfs]

```
CONFIG_TMPFS_XATTR=y
CONFIG_TMPFS_POSIX_ACL=y
```

Required for KSU module overlays to work. Don't disable unless you know what you're doing.

### [performance]

Debug options that may be enabled by your device's vendor config. **All commented out by default.** Check `/proc/config.gz` on your device first — only uncomment if these are actually set in your base config.

Disabling them reduces lock contention and improves throughput, but removes kernel debug safety nets.

### [kpm]

```
CONFIG_KPM=y
```

Kernel Patch Manager. Enables runtime kernel patching support.

---

## KSU Variants

Each variant is a different fork of KernelSU. The CI checks out the exact commit specified in the pin file, applies patches, and builds.

| Variant | Fork | Pin File |
|---------|------|----------|
| SukiSU Ultra | [SukiSU-Ultra/SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra) | `sukisu-pin.txt` |
| SukiSU Ultra (LKM) | [SukiSU-Ultra/SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra) `main` | `sukisu-lkm-pin.txt` (optional) |
| ReSukiSU | [ReSukiSU/ReSukiSU](https://github.com/ReSukiSU/ReSukiSU) | `resukisu-pin.txt` |
| KernelSU-Next | [KernelSU-Next/KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) | `kernelsu-next-pin.txt` |
| WildKSU | [WildKernels/Wild_KSU](https://github.com/WildKernels/Wild_KSU) | `wksu-pin.txt` |

**SukiSU pin must point to the `builtin` branch.** The `main` branch lacks `CONFIG_KSU_SUSFS` in its Kconfig, which means `fs/susfs.o` never compiles and the build fails with undefined symbol errors at link time.

To update a pin: change the commit hash in the pin file. Test with dry-test first.

---

## Build Helpers

Scripts in `build-helpers/` are called by CI at specific stages. They handle differences between kernel sublevels so the same patches work across the full sublevel range.

| Script | Stage | Purpose |
|--------|-------|---------|
| `assemble-defconfig.sh` | Pre-build | Merges GKI base defconfig + `defconfig.fragment` into final `.config` |
| `fix-old-kernel-compat.sh` | Pre-patch | Fixes vanilla kernel issues on older sublevels (missing includes, etc.) |
| `fix-susfs-compat.sh` | Post-patch | Fixes sublevel-dependent SUSFS issues. Idempotent — safe to run multiple times. |
| `bypass-abi-check.sh` | Pre-build | Skips GKI ABI compliance checks. Custom kernels break the stable driver ABI by design. |
| `clean-build-flags.sh` | Pre-build | Strips debug/test config options for production builds. |
| `clean-module-list.sh` | Pre-build | Removes modules not needed for the target device. |
| `report-config.sh` | Post-config | Prints enabled features to CI logs for verification. |
| `setup-bbg.sh` | Pre-build | Configures BBG support. |
| `setup-droidspaces.sh` | Post-patch | Applies Droidspaces GKI kABI patches. **Fails the build** on any patch problem. |
| `setup-extra-features.sh` | Post-patch | Applies BBRv3 / NTSync feature patches. **Fails the build** on any patch problem. |

---

## Building

### From GitHub Actions UI

1. Go to **Actions** → pick the workflow for your variant (`build-sukisu.yml`, `build-resukisu.yml`, etc.)
2. Click **Run workflow**
3. Fill in: `android_version`, `kernel_version`, `sub_level`, `os_patch_level`
4. Toggle feature flags as needed (all default to on except `add_bbg` and `add_kpm`)

### From CLI

```bash
# Single target build (all variants)
gh workflow run kernel-custom.yml --ref main \
  -f kernel_target="android12-5.10.209 (2024-05)"

# Specific variant
gh workflow run build-sukisu.yml --ref main \
  -f android_version=android12 \
  -f kernel_version=5.10 \
  -f sub_level=209 \
  -f os_patch_level=2024-05
```

### Feature Flags

| Flag | Default | Controls |
|------|---------|----------|
| `add_susfs` | true | Applies 50_ + 51_ patches |
| `add_zeromount` | true | Applies 60_ patch |
| `add_zram` | true | Enables ZRAM config section |
| `add_overlayfs_support` | true | Enables overlayfs config section |
| `add_bbg` | false | Runs `setup-bbg.sh` |
| `add_kpm` | false | Enables KPM config section |
| `add_droidspaces` | false | Applies Droidspaces kABI patches + enables IPC/namespace configs |
| `add_bbrv3` | true | Backports TCP BBRv3 and makes it the default congestion control |
| `add_ntsync` | true | Adds NTSync (NT synchronization primitive emulation) |
| `build_lkm` | true | Builds `kernelsu.ko` alongside the kernel (SukiSU variant only) |

### Extra Feature Patches

`setup-extra-features.sh` pulls optional feature patches from the `kernel_patches` artifact (`common/bbrv3/`, `common/ntsync/`). Failures are fatal here — unlike the micro-optimisations in `apply-kernel-patches.sh`, a skipped patch would leave the defconfig referencing Kconfig symbols that do not exist.

| Feature | Patches | Adds |
|---------|---------|------|
| BBRv3 | `0001-net-tcp-backport-BBRv3-to-android12-5.10.patch` (+ `sysctl_*` backports when needed) | `CONFIG_TCP_CONG_BBR3`, `net/ipv4/tcp_bbr3.c`, `net/ipv4/tcp_plb.c` |
| NTSync | `ntsync_base.patch` + `ntsync_compat_android12-5.10.patch` | `CONFIG_NTSYNC`, `drivers/misc/ntsync.c` |

> [!NOTE]
> `add_bbrv3` sets `CONFIG_DEFAULT_TCP_CONG="bbr3"` — it does not just make BBRv3 available, it becomes the system default. Stock BBR (`CONFIG_TCP_CONG_BBR`) and CUBIC stay compiled in.

Two details worth knowing:

- **The BBRv3 sysctl backports are conditional.** `proc_dou8vec_minmax` is already in 5.10.246 (`include/linux/sysctl.h`, `kernel/sysctl.c`), so the script skips them; older sublevels get them applied. Applying them unconditionally fails with "previously applied".
- **NTSync ships two compat variants.** `ntsync_compat_android12-5.10.patch` and `..._A14.patch` target different `include/linux/lockdep.h` baselines. The script dry-runs each and uses the one that fits, failing if neither does. On 5.10.246 the non-A14 variant is correct.

### Already integrated elsewhere

Several commonly-requested `kernel_patches/common` items are already wired up and need no separate toggle:

| Feature | Where |
|---------|-------|
| Unicode bypass fix | `apply-kernel-patches.sh` (`unicode_bypass_fix_6.1-.patch` for < 6.1) |
| IPv6 NAT fix | `apply-kernel-patches.sh` (`IPv6_NAT_FIX.patch`) |
| Kernel optimisation | `apply-kernel-patches.sh` (22 patches, gated by `add_perf_patches`) |
| IP Set | `defconfig.fragment` `[base]` (21 `CONFIG_IP_SET*` entries) |
| TTL / HL target | `defconfig.fragment` `[base]` (`IP_NF_TARGET_TTL`, `IP6_NF_TARGET_HL`, `IP6_NF_MATCH_HL`) |
| CAKE / PIE qdisc | `defconfig.fragment` `[base]` — config-only, the Kconfig symbols already exist in 5.10 |

### Droidspaces (GKI container support)

Enables [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS) by turning on `CONFIG_SYSVIPC`, `CONFIG_POSIX_MQUEUE`, `CONFIG_IPC_NS`, `CONFIG_PID_NS` and friends.

> [!CAUTION]
> **The kABI patches are not optional.** Enabling those configs on a GKI kernel shifts `task_struct` / `user_struct` offsets, and pre-compiled vendor modules (GPU, camera) then read the wrong fields — immediate bootloop. `setup-droidspaces.sh` moves the new fields into `ANDROID_KABI_RESERVE` padding so offsets stay put.

Because a silently-skipped patch here produces an unbootable image, `setup-droidspaces.sh` fails the build on any patch problem — no `-F` fuzz, `--batch` so `patch` can never prompt or reverse-apply, `--forward` so an already-applied tree errors instead of being undone. This is deliberately stricter than `apply-kernel-patches.sh`, which tolerates failures with `|| true`.

Patches come from the `kernel_patches` artifact (`common/droidspaces/`), already downloaded by every build — nothing is vendored here.

| Patch | Target | Applies to |
|-------|--------|-----------|
| `fix_sysvipc_kabi_6_7_8.patch` | `include/linux/sched.h` | < 6.12 |
| `fix_sysvipc_kabi_a16-6.12.patch` | `include/linux/sched.h` | ≥ 6.12 |
| `fix_abi_padding_for_posix_mqueue.patch` | `include/linux/sched/user.h` | ≤ 5.10 |
| `0001-Guard-USER_NS-for-non-root-users.patch` | `kernel/user_namespace.c` | all |

The last one is hardening, not a Droidspaces requirement: `CONFIG_USER_NS=y` otherwise lets any app create user namespaces, a well-known local privilege escalation surface. It gates creation behind `CAP_SYS_ADMIN`, so root-run containers still work.

Verified applying cleanly (zero fuzz) against `android12-5.10-2025-12` (5.10.246). **Only android12-5.10 is wired up** — `setup-droidspaces.sh` lives in this directory only, and the build step fails loudly if another version enables the flag without it.

If the sysvipc patch bootloops, upstream ships `fix_sysvipc_kabi_1_2_3.patch` and `fix_sysvipc_kabi_3_4_5.patch` using different KABI slots; on 5.10.246 slots 6/7/8 are free (1 and 2 are taken by `pf_io_worker`) so `6_7_8` is correct here.


### SukiSU LKM

`kernel-a12-5.10.yml` runs a `build-sukisu-lkm` job in parallel with the normal kernel build when `build_lkm` is on and `ksu_variant` is `SukiSU`. It produces a loadable `kernelsu.ko` for **stock** `android12-5.10` kernels — no kernel rebuild, no AnyKernel3 zip. Flash it with `ksud`.

The job runs inside `ghcr.io/ylarod/ddk-min:android12-5.10-<ddk_release>`, which ships the DDK headers, `KDIR`, and clang. Build is `CONFIG_KSU=m CC=clang make` in SukiSU's `kernel/` directory, mirroring SukiSU's own `ddk-lkm.yml`. Output is aarch64 only.

| Input | Default | Controls |
|-------|---------|----------|
| `sukisu_lkm_commit` | `""` | SukiSU commit for the LKM. Empty → `sukisu-lkm-pin.txt`, then `main`. |
| `ddk_release` | `20260313` | Date tag of the DDK image. Set in `build-sukisu-lkm.yml`. |

> [!IMPORTANT]
> **The LKM has no SUSFS.** LKM requires `CONFIG_KSU` to be `tristate`, which only SukiSU's `main` branch declares — and `main` carries zero `CONFIG_KSU_SUSFS` entries and no susfs sources. The `builtin` branch used for the normal build declares `CONFIG_KSU` as `bool` and cannot produce a `.ko`. SUSFS and LKM are mutually exclusive upstream, so ZeroMount does not work on LKM builds.

This is why the LKM uses a separate pin (`sukisu-lkm-pin.txt`, `main` branch) from `sukisu-pin.txt` (`builtin` branch). The file is optional — if absent, the job tracks `main`.

### Dry-Testing (Patch Validation)

Validates that patches apply cleanly to the kernel source without compiling. Run this before full builds to catch patch conflicts early.

```bash
# Single sublevel
gh workflow run dry-test-patches.yml --ref main \
  -f android_version=android12 \
  -f kernel_version=5.10 \
  -f sub_level=209 \
  -f os_patch_level=2024-05 \
  -f mode=single

# All sublevels for this kernel version
gh workflow run dry-test-patches.yml --ref main \
  -f android_version=android12 \
  -f kernel_version=5.10 \
  -f mode=matrix
```

---

## Version-Specific Notes

Not all kernel versions are identical. Key differences:

| Kernel | Variants | Notable Differences |
|--------|----------|---------------------|
| 5.4 | 2 (SukiSU, ReSukiSU) | Pre-GKI. Requires `UAPI_HEADER_TEST=n`. No KSU-Next/WKSU (lack `TWA_RESUME`). Single sublevel (302 LTS). |
| 5.10 | 4 | Baseline GKI. Has `HIDDEN_NAME` and `HARDENED` toggles (unique to 5.10). |
| 5.15 | 4 | `struct nameidata` natively has `state` field (upstream patch adds it redundantly). |
| 6.1 | 4 | `vfs_statx` takes `struct filename *`. `inode_permission` gained `mnt_userns` parameter. |
| 6.6 | 4 | `SUS_PATH` absent from defconfig (not supported). `do_faccessat`/`do_sys_openat2` moved to `fs/open.c`. |
| 6.12 | 4 | `SUS_PATH=n` (AS_FLAGS bit collision). LTO disabled (`none`). `fd_file()` accessor replaces `f.file`. |

---

## Updating Patches

**50_ (upstream SUSFS):** Replace with the latest from [susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu). After replacing, always re-test 51_ — context lines may have shifted.

**51_ (enhancements):** Must be regenerated if 50_ changes. Apply 50_ to a clean kernel source, make your changes, diff against the post-50_ tree.

**60_ (ZeroMount):** Independent of 50_/51_. Update separately.

**70_ (KSU safety):** Regenerate when pinning to a new KSU fork commit. Diff the fork's `kernel/` directory to find what needs fixing.

After any patch update: dry-test → smoke build (lowest + highest sublevel) → full matrix.
