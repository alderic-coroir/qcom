# Qualcomm Silicon Workshop — Design Document

**Status:** Draft v2 — awaiting implementation authorization  
**Target platform:** Qualcomm Dragonwing™ IQ-9075 Evaluation Kit (EVK)  
**Target Ubuntu release:** Ubuntu 24.04 LTS (Noble) — only  
**Architecture contract:** `SILICON_WORKSHOP_CONTRACT.md`  
**Date:** 2026-08-10

---

## Evidence Summary

This document is grounded in direct inspection of:

- Canonical image manifests (server + desktop, 20260710 build)
- IQ9 YAML metadata (`ubuntu-24.04-preinstalled-server-arm64+dragonwing-x13-20260710-iq9.yaml`)
- `linux-qcom` Noble Launchpad Git at tag `Ubuntu-qcom-6.8.0-1080.85`
  (commit `36646c64159f94636a17f59b949863ba3702ebab`)
- Key source files inspected verbatim:
  `debian/rules`, `debian/rules.d/0-common-vars.mk`,
  `debian/rules.d/2-binary-arch.mk`, `debian/rules.d/3-binary-indep.mk`,
  `debian.qcom/rules.d/arm64.mk`, `debian.qcom/control.stub.in`,
  `debian.qcom/control.d/vars.qcom`, `debian.qcom/config/annotations`,
  `debian.qcom/patch/msm_default.diff`,
  `arch/arm64/boot/dts/qcom/qcs9075-iq-9075-evk.dts`
- Current Snapcraft Kernel plugin source:
  `snapcraft/parts/plugins/kernel_plugin.py`, `kernel_build.sh`
- Current `craft-archives` source:
  `craft_archives/repo/package_repository.py`,
  `craft_archives/repo/apt_sources_manager.py`
- `iot-field-kernel-snap` `snapcraft.yaml` template (Canonical reference)

---

## Reference Platform

### SoC Identity and Naming

The Qualcomm Dragonwing IQ-9075 EVK is built on the **QCS9075** SoC.

**Evidence from `qcs9075-iq-9075-evk.dts`:**

```
model = "Qualcomm Technologies, Inc. IQ 9075 EVK";
compatible = "qcom,qcs9075-iq-9075-evk", "qcom,qcs9075", "qcom,sa8775p";
```

**Naming hierarchy (verified from DTS source tree):**

| Term | Value | Meaning |
|---|---|---|
| SoC | QCS9075 | The actual silicon on the IQ-9075 board |
| SoC base / IP | SA8775P | The SA8775P automotive SoC that QCS9075 derives from |
| Board | IQ-9075 EVK | Qualcomm Dragonwing evaluation kit |
| Firmware family | QCS9100 | The firmware artifact family (covers SA8775P-derived SoCs) |

QCS9075 is an industrial variant of the SA8775P that shares its DTS base
(`sa8775p.dtsi`) and firmware artifacts (`QCS9100/QLI.1.7-Ver.1.1`).

**CPU architecture:** `arm64` (AArch64)

**Correct config terminology:**
- `silicon.soc: qcs9075` — the silicon on the board
- `silicon.board: iq-9075-evk` — the board name

### Current Known-Good Ubuntu 24.04 Kernel

| Field | Value | Source |
|---|---|---|
| Source package | `linux-qcom` | Manifests |
| Kernel flavour | `qcom` | `debian.env`, `arm64.mk` |
| Binary kernel version | `6.8.0-1080.85` | Server + Desktop manifests |
| ABI number | `1080` | Derived from version |
| Upload revision | `85` | Derived from version |
| Git tag | `Ubuntu-qcom-6.8.0-1080.85` | Launchpad API |
| Git commit | `36646c64159f94636a17f59b949863ba3702ebab` | Launchpad API |
| Kernel image | `Image.gz` | `arm64.mk: build_image = Image.gz` |
| Modules release dir | `6.8.0-1080-qcom` | Derived (see KERNELRELEASE section) |

**Server and Desktop use the same kernel build.** Both manifests show
identical `linux-image-6.8.0-1080-qcom 6.8.0-1080.85` entries.

### Authoritative Kernel Source

**Git HTTPS URL:**
`https://git.launchpad.net/~canonical-kernel/ubuntu/+source/linux-qcom/+git/noble`

**Default branch:** `master`

**Tag for current image:** `Ubuntu-qcom-6.8.0-1080.85`  
**Commit:** `36646c64159f94636a17f59b949863ba3702ebab`

The tag pattern is: `Ubuntu-qcom-<upstream>-<abi>.<upload>`

### Device Trees (IQ-9075)

The primary EVK DTS file is:

```
arch/arm64/boot/dts/qcom/qcs9075-iq-9075-evk.dts
```

Resulting DTB: **`qcs9075-iq-9075-evk.dtb`**

This DTS includes `sa8775p.dtsi` and `qcs9075-thermal.dtsi`.
It uses the `qcom,sa8775p` compatible fallback.

Additional overlays exist (camera, mezzanine, addons) but are not required
for a baseline build. Recorded here for future reference:

```
qcs9075-addons-iq-9075-evk.dts
qcs9075-addons-iq-9075-evk-mezz.dtso
qcs9075-camera-iq-9075-evk.dts
qcs9075-camera-iq-9075-evk.dtso
```

### Compiler / Toolchain

From `debian/rules.d/0-common-vars.mk`:

```makefile
gcc ?= gcc-13
CC=$(CROSS_COMPILE)$(gcc)
CROSS_COMPILE ?= $(DEB_HOST_GNU_TYPE)-
```

The main kernel compilation uses **gcc-13**. `clang-18` appears in
`Build-Depends` for Rust kernel module support only (`rustc`, `rust-src`,
`bindgen-0.65`). It is not the primary C compiler.

For cross-compilation (amd64 host → arm64 target):
`CROSS_COMPILE=aarch64-linux-gnu-`, package `gcc-13-aarch64-linux-gnu`

### Firmware

Two firmware artifacts exist in the reference image:

1. **`linux-firmware-dragonwing 20260613`** — runtime firmware package.
   **Not a kernel build dependency.** The `linux-image-*-qcom` package
   depends on `linux-firmware` (generic), not `linux-firmware-dragonwing`.

2. **NHLOS firmware (`QCS9100/QLI.1.7-Ver.1.1`)** — bootloader-level
   firmware, consumed before the kernel boots. Out of scope.

The kernel build itself requires no firmware at build time.

### SAUCE Patches

All SAUCE patches are carried inside the `linux-qcom` git history.
Cloning the tag produces a tree with patches already applied.
There are no external patch files to apply before building.

The `msm_default` SAUCE patches are handled differently — see next section.

---

## `msm_default`: Fully Resolved

### What it is

`msm_default` is a **copy of `drivers/gpu/drm/msm`** with a small
compatibility patch applied (`debian.qcom/patch/msm_default.diff`).
The copy lives at `drivers/gpu/drm/msm_default`.

**It is not a defconfig. It is not an input to the kernel configuration
system.** It is a source-tree modification for the Qualcomm GPU driver
packaging integration.

### When it is created

The `msm_default` directory is created inside `debian/rules clean`:

```makefile
# From debian/rules clean target (verified verbatim):
rm -rf drivers/gpu/drm/msm_default
cp -r drivers/gpu/drm/msm drivers/gpu/drm/msm_default
patch -p1 < $(DEBIAN)/patch/msm_default.diff
```

This runs when `fakeroot debian/rules clean` is invoked — i.e., as the
first step of the **Debian SDK** build path only.

### Impact on Kernel SDK direct build

**CORRECTION from initial analysis (discovered during implementation):**
`msm_default` IS required for the direct `make` build.

The SAUCE patches also modify `drivers/gpu/drm/Makefile` to add:
```makefile
obj-$(CONFIG_DRM_MSM) += msm_default/
```
Since `CONFIG_DRM_MSM=m` in the qcom flavour annotations, the kernel build
attempts to compile `drivers/gpu/drm/msm_default/` — which does not exist
in the git tree and fails with:
```
No rule to make target '.../drivers/gpu/drm/msm_default/Makefile'. Stop.
```

**Resolution:** The Kernel SDK `configure.sh` creates `msm_default/` as
part of the configuration step, replicating the `debian/rules clean` logic:
```bash
cp -r drivers/gpu/drm/msm drivers/gpu/drm/msm_default
patch -p1 < debian.qcom/patch/msm_default.diff
```
This is done once per worktree checkout, before the kernel build.

**Conclusion: `msm_default` IS needed for the direct Kernel SDK build.
It is created by `configure.sh` before compilation. OQ-8 is resolved —
but with the opposite conclusion from the initial analysis.**

---

## KERNELRELEASE: Verified Derivation

### How the Ubuntu packaging derives the string

From `debian/rules.d/0-common-vars.mk` (verified verbatim):

```
version     = 6.8.0-1080.85       (from debian.qcom/changelog)
revision    = 1080.85              (last component after '-')
release     = 6.8.0-1080          (version minus revision)
abinum      = 1080                 (first component of revision)
abi_release = 6.8.0-1080          (release-abinum = same)

KERNELRELEASE = abi_release-flavour = 6.8.0-1080-qcom
```

This creates `/lib/modules/6.8.0-1080-qcom/` and names the binary packages
`linux-image-6.8.0-1080-qcom`, etc.

### Kernel SDK derivation

The Kernel SDK reads the tag value from `config/workshop.yaml`
(`Ubuntu-qcom-6.8.0-1080.85`) and applies the same formula in
`sdk/kernel/lib/common.sh`:

```bash
# Input: Ubuntu-qcom-6.8.0-1080.85
# Strip prefix:     6.8.0-1080.85
# Extract revision: 1080.85  → abinum=1080
# Extract release:  6.8.0-1080
# KERNELRELEASE = 6.8.0-1080-qcom  (flavour read from debian.env)
```

The Kernel SDK does not invent an arbitrary string. It derives the same
KERNELRELEASE as the Ubuntu packaging would.

### CONFIG_VERSION_SIGNATURE

The `stamp-prepare-tree-%` target also sets:

```
CONFIG_VERSION_SIGNATURE="Ubuntu 6.8.0-1080.85-qcom 6.8.0"
```

The Kernel SDK replicates this in the `configure.sh` step after the
annotations export and before `olddefconfig`.

---

## Repository Structure

### Source Isolation Design

A single **bare git clone** is created at `cache/linux-qcom.git/` and is
never modified after fetching. Each SDK creates an independent **git
worktree** from this shared object store.

```
cache/linux-qcom.git/       ← bare clone (shared, never modified by SDKs)
src/kernel/linux-qcom/      ← Kernel SDK worktree
src/deb/linux-qcom/         ← Debian SDK worktree
```

Benefits:
- Source download happens once regardless of how many times SDKs run.
- `fakeroot debian/rules clean` in the Deb SDK worktree does not affect
  the Kernel SDK worktree.
- Each SDK can rebuild independently.

### Full Repository Layout

```
workshop_catalog/qcom/
│
├── SILICON_WORKSHOP_CONTRACT.md
├── CLAUDE.md
├── README.md
├── QUALCOMM_WORKSHOP_DESIGN.md
│
├── config/
│   └── workshop.yaml
│
├── sdk/
│   ├── kernel/
│   │   ├── bin/
│   │   │   ├── kernel-build      ← public command
│   │   │   └── kernel-clean      ← public command
│   │   └── lib/
│   │       ├── common.sh         ← config reading, version derivation
│   │       ├── fetch.sh          ← bare clone + worktree management
│   │       ├── configure.sh      ← annotations export + .config
│   │       ├── build.sh          ← make invocations
│   │       ├── stage.sh          ← artifact normalization
│   │       └── validate.sh
│   │
│   ├── deb/
│   │   ├── bin/
│   │   │   └── kernel-build-debs ← public command
│   │   └── lib/
│   │       ├── common.sh
│   │       ├── fetch.sh          ← worktree management (reuses cache/)
│   │       ├── build.sh          ← debian/rules invocation
│   │       ├── stage.sh
│   │       └── validate.sh
│   │
│   └── snap/
│       ├── bin/
│       │   └── kernel-build-snap ← public command
│       ├── lib/
│       │   ├── common.sh
│       │   ├── repo.sh           ← GPG key + apt-ftparchive
│       │   └── validate.sh
│       └── snapcraft/
│           └── snapcraft.yaml.template
│
├── cache/                         ← gitignored
│   └── linux-qcom.git/            ← bare git clone
│
├── src/                           ← gitignored
│   ├── kernel/linux-qcom/         ← Kernel SDK worktree
│   └── deb/linux-qcom/            ← Debian SDK worktree
│
├── build/                         ← gitignored
│   ├── kernel/
│   │   ├── build-qcom/
│   │   └── modules-staging/
│   └── snap/
│
└── out/                           ← gitignored
    ├── kernel/
    ├── deb/
    └── snap/
```

---

## Configuration

### Philosophy

Configuration describes **what** to build. SDK code describes **how**.

Only fields that vary per BSP or build environment are in `workshop.yaml`.
Fields fixed for this Workshop (toolchain version, image format, flavour
name) are encoded in SDK scripts.

### Field Classification

| Candidate field | Decision | Reason |
|---|---|---|
| `silicon.vendor` | Include | BSP identity |
| `silicon.soc` | Include | Drives DTS selection |
| `silicon.board` | Include | Drives board-specific filenames |
| `ubuntu.release` | Include | BSP configuration |
| `kernel.repository` | Include | BSP configuration |
| `kernel.ref` | Include | BSP configuration |
| `kernel.flavour` | **Drop** | Fixed for this Workshop. SDK reads `debian.env` from the source tree. |
| `kernel.image` | **Drop** | Fixed to `Image.gz` for arm64. SDK reads `arm64.mk`. |
| `kernel.device_trees` | Include | Varies per board |
| `toolchain.cross_compile` | Include | May vary by build environment |
| `toolchain.gcc` | **Drop** | Fixed to `gcc-13`. SDK encodes this. |
| `build.jobs` | **Drop** | Operational, not BSP. SDK uses `nproc`; override via `WORKSHOP_JOBS` env var. |

### `config/workshop.yaml`

```yaml
# Qualcomm Silicon Workshop — Project Configuration
# Schema version 1

schema_version: 1

silicon:
  vendor: qualcomm
  soc: qcs9075             # The SoC on the IQ-9075 board
  board: iq-9075-evk       # Board identifier

ubuntu:
  release: noble           # Ubuntu 24.04 LTS

kernel:
  repository: https://git.launchpad.net/~canonical-kernel/ubuntu/+source/linux-qcom/+git/noble
  ref:
    type: tag
    value: Ubuntu-qcom-6.8.0-1080.85
  device_trees:
    - qcs9075-iq-9075-evk.dtb

toolchain:
  cross_compile: aarch64-linux-gnu-   # Set to "" for native arm64 builds
```

### Values the SDK derives internally (not in config)

| Derived value | Source |
|---|---|
| `FLAVOUR` | `debian.env` in the checked-out source: `DEBIAN=debian.qcom` → `qcom` |
| `KERNELRELEASE` | Parsed from `kernel.ref.value`: `Ubuntu-qcom-6.8.0-1080.85` → `6.8.0-1080-qcom` |
| Kernel image target | `debian.<flavour>/rules.d/arm64.mk`: `build_image = Image.gz` |
| Compiler | `gcc-13` (hardcoded; matches `control.stub.in`) |

### Future BSP Specialization

A future agent changes in `config/workshop.yaml`:

- `silicon.soc`, `silicon.board`
- `kernel.ref`
- `kernel.device_trees`
- `toolchain.cross_compile` (if environment differs)

No SDK scripts need to change for normal BSP specialization.

---

## Kernel SDK

### Responsibilities

1. Fetch and cache the `linux-qcom` source (bare clone + worktree).
2. Generate kernel `.config` from the Ubuntu annotations system.
3. Build kernel image, DTBs, and modules via direct `make`.
4. Normalize artifacts to `out/kernel/`.
5. Validate required outputs.

### Source Management

```bash
# First run (or --all clean):
git clone --bare <repository> cache/linux-qcom.git

# Every run:
git -C cache/linux-qcom.git fetch --tags
git worktree add src/kernel/linux-qcom <ref.value>    # first time
git -C src/kernel/linux-qcom checkout <ref.value>     # subsequent
```

`kernel-clean --all` removes `src/kernel/linux-qcom/` but not
`cache/linux-qcom.git/`.

### Verified Config Generation Sequence

Taken directly from `stamp-prepare-tree-%` in `2-binary-arch.mk`:

```bash
# In sdk/kernel/lib/configure.sh:

# 1. Derive FLAVOUR from debian.env
FLAVOUR=$(grep '^DEBIAN=' src/kernel/linux-qcom/debian/debian.env \
          | cut -d= -f2 | sed 's/debian\.//')
# → qcom

# 2. Create build directory
mkdir -p build/kernel/build-${FLAVOUR}
touch build/kernel/build-${FLAVOUR}/ubuntu-build

# 3. Export .config from annotations
python3 src/kernel/linux-qcom/debian/scripts/misc/annotations \
    --export \
    --arch arm64 \
    --flavour "${FLAVOUR}" \
    > build/kernel/build-${FLAVOUR}/.config

# 4. Set CONFIG_VERSION_SIGNATURE
#    (derived from kernel.ref.value by common.sh)
KERNELRELEASE="6.8.0-1080-qcom"   # computed
RELEASE="6.8.0-1080"
REVISION="85"
sed -i "s/.*CONFIG_VERSION_SIGNATURE.*/CONFIG_VERSION_SIGNATURE=\
\"Ubuntu ${RELEASE}-${REVISION}-${FLAVOUR} 6.8.0\"/" \
    build/kernel/build-${FLAVOUR}/.config

# 5. Resolve config
make -C src/kernel/linux-qcom \
     O="$(pwd)/build/kernel/build-${FLAVOUR}" \
     ARCH=arm64 \
     olddefconfig
```

Note: `msm_default` is NOT involved in this sequence.

### Build Steps

```bash
# sdk/kernel/lib/build.sh  (all variables set by common.sh + configure.sh)

ARCH=arm64
CROSS_COMPILE=${cross_compile}           # from config
CC="${CROSS_COMPILE}gcc-13"
KERNELRELEASE="6.8.0-1080-qcom"         # computed
JOBS=${WORKSHOP_JOBS:-$(nproc)}
SRC=src/kernel/linux-qcom
BUILD="$(pwd)/build/kernel/build-${FLAVOUR}"

make -C "${SRC}" O="${BUILD}" \
     ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" CC="${CC}" \
     KERNELRELEASE="${KERNELRELEASE}" -j"${JOBS}" Image.gz

make -C "${SRC}" O="${BUILD}" \
     ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" CC="${CC}" \
     -j"${JOBS}" dtbs

make -C "${SRC}" O="${BUILD}" \
     ARCH="${ARCH}" CROSS_COMPILE="${CROSS_COMPILE}" CC="${CC}" \
     -j"${JOBS}" modules

make -C "${SRC}" O="${BUILD}" \
     ARCH="${ARCH}" \
     INSTALL_MOD_PATH="$(pwd)/build/kernel/modules-staging" \
     -j"${JOBS}" modules_install
```

### Artifact Normalization

| Source path | Normalized output |
|---|---|
| `build/kernel/build-qcom/arch/arm64/boot/Image.gz` | `out/kernel/image/Image.gz` |
| (symlink) | `out/kernel/image/vmlinuz → Image.gz` |
| `build/kernel/build-qcom/arch/arm64/boot/dts/qcom/qcs9075-iq-9075-evk.dtb` | `out/kernel/dtbs/qcs9075-iq-9075-evk.dtb` |
| `build/kernel/modules-staging/lib/modules/6.8.0-1080-qcom/` | `out/kernel/modules/6.8.0-1080-qcom/` |
| `build/kernel/build-qcom/.config` | `out/kernel/metadata/config` |
| `build/kernel/build-qcom/System.map` | `out/kernel/metadata/System.map` |
| (computed) | `out/kernel/metadata/kernel-version` (e.g. `6.8.0-1080-qcom`) |
| (computed) | `out/kernel/metadata/build-info.yaml` |

Only DTBs listed in `kernel.device_trees` are staged.

### Public Commands

**`kernel-build [--config path]`**

Complete workflow: validate → fetch → configure → build → stage → validate.
Exits non-zero on any failure.

**`kernel-clean [--all]`**

Removes `build/kernel/` and `out/kernel/`.
Does NOT remove `cache/linux-qcom.git/` or `src/kernel/linux-qcom/`.
`--all` additionally removes `src/kernel/linux-qcom/` (the worktree).

### Automatic Validation

- `out/kernel/image/Image.gz` exists; `file` identifies it as gzip data
- `out/kernel/image/vmlinuz` symlink exists
- Each DTB in `kernel.device_trees` present in `out/kernel/dtbs/`
- `out/kernel/modules/<KERNELRELEASE>/modules.dep` exists
- `out/kernel/metadata/kernel-version` matches expected KERNELRELEASE

---

## Debian Packaging SDK

### Responsibilities

Produce proper Ubuntu kernel Debian packages from the `linux-qcom` source
tree using `debian/rules`. This is the packaging boundary between raw
kernel source and the downstream snap build.

### Source Management

Same bare clone `cache/linux-qcom.git/`. Independent worktree at
`src/deb/linux-qcom/`. The Debian SDK is the only SDK that modifies its
worktree (via `debian/rules clean`).

### Verified Build Command Sequence

The following is derived from direct inspection of `debian/rules` and
`debian/rules.d/2-binary-arch.mk`:

```bash
cd src/deb/linux-qcom/

# 1. Prepare source tree
#    Creates: msm_default, debian/control, reconstruct state
fakeroot debian/rules clean

# 2. Compile the kernel (both qcom and qcom-rt, per flavours= in arm64.mk)
#    For Snap SDK, only qcom is needed. The rules do not support building
#    a single flavour in isolation at this stage.
fakeroot debian/rules build-qcom

# 3. Package the qcom flavour
#    Produces: linux-image-*, linux-modules-*, linux-headers-*,
#              linux-tools-*, linux-buildinfo-*, linux-*-lib-rust-*
fakeroot debian/rules binary-qcom

# 4. Package architecture-independent header packages
#    Produces: linux-qcom-headers-<abi>_*.deb (arch: all)
#              linux-libc-dev-qcom_*.deb
#    NOTE: This is required by binary-arch-deps-true in 2-binary-arch.mk
fakeroot debian/rules binary-arch-headers
```

**Cross-compilation (amd64 host → arm64 packages):**

```bash
export DEB_BUILD_ARCH=amd64
export DEB_HOST_ARCH=arm64
# then run the above targets
```

This is architecturally supported per `control.stub.in`
(`gcc-13-aarch64-linux-gnu <cross>` in Build-Depends) and
`0-common-vars.mk` (`CROSS_COMPILE ?= $(DEB_HOST_GNU_TYPE)-`).
**Whether it works without errors requires a build test (OQ-1).**

### Package Output Classification

| Package | Required by Snap SDK | Ubuntu Classic | Notes |
|---|---|---|---|
| `linux-image-6.8.0-1080-qcom_*.deb` | **Yes** | Yes | Kernel image + DTBs |
| `linux-modules-6.8.0-1080-qcom_*.deb` | **Yes** | Yes | Kernel modules |
| `linux-headers-6.8.0-1080-qcom_*.deb` | No | Yes | Flavour headers |
| `linux-qcom-headers-6.8.0-1080_*.deb` | No | Yes | Common headers (arch: all) |
| `linux-tools-6.8.0-1080-qcom_*.deb` | No | Optional | perf, bpftool, etc. |
| `linux-libc-dev-qcom_*.deb` | No | Optional | Userspace headers |
| `linux-buildinfo-6.8.0-1080-qcom_*.deb` | No | Optional | Build metadata |

All produced packages are staged to `out/deb/` regardless.

### `kernel-build-debs`

```
Usage: kernel-build-debs [--config path]

Performs:
  1. Ensure src/deb/linux-qcom/ at correct revision
  2. Check build dependencies
  3. fakeroot debian/rules clean
  4. fakeroot debian/rules build-<flavour>
  5. fakeroot debian/rules binary-<flavour>
  6. fakeroot debian/rules binary-arch-headers
  7. Move .deb files from src/deb/linux-qcom/../ → out/deb/
  8. Write out/deb/metadata/
  9. Validate
```

### Output Layout

```
out/deb/
├── linux-image-6.8.0-1080-qcom_6.8.0-1080.85_arm64.deb
├── linux-modules-6.8.0-1080-qcom_6.8.0-1080.85_arm64.deb
├── linux-headers-6.8.0-1080-qcom_6.8.0-1080.85_arm64.deb
├── linux-qcom-headers-6.8.0-1080_6.8.0-1080.85_all.deb
├── linux-tools-6.8.0-1080-qcom_6.8.0-1080.85_arm64.deb
├── linux-libc-dev-qcom_6.8.0-1080.85_all.deb
├── Packages             ← APT index created by Snap SDK at snap-build time
└── metadata/
    ├── package-list.txt
    ├── kernel-version   ← "6.8.0-1080.85"
    └── flavour          ← "qcom"
```

### Automatic Validation

- `linux-image-*-qcom_*.deb` and `linux-modules-*-qcom_*.deb` exist
- `dpkg-deb --info` succeeds on each package
- `dpkg -c linux-image-*-qcom*.deb | grep vmlinuz` succeeds

---

## Snap Packaging SDK

### Responsibilities

Produce an Ubuntu Core kernel snap from locally produced Debian packages
using `plugin: kernel`. Does not compile the kernel.

### Verified Snapcraft Configuration

**For Ubuntu 24.04 (Noble):**

- `build-base: core24`
- `type: kernel`
- No `base:` key (kernel snaps do not use `base:`)

**Evidence:** The official `iot-field-kernel-snap` template explicitly
states: *"Kernels should be built based on the release of Ubuntu Core being
targeted, but do not otherwise require a base as all other snaps do. As
such, only a `build-base` is required"*. Confirmed by Snapcraft project
model source.

### Local Debian Package Integration

**CANDIDATE DESIGN — REQUIRES INTEGRATION TEST**

#### Verified by source inspection

| Claim | Status | Evidence |
|---|---|---|
| `craft-archives` accepts `FileUrl` for package-repositories | **VERIFIED** | `PackageRepositoryApt.url: AnyUrl \| FileUrl` |
| `key-id` is required (40-char hex) | **VERIFIED** | Non-optional field; `KeyIdStr` pattern `[0-9A-F]{40}` |
| `suites: [/]` in YAML is invalid | **VERIFIED** | `SuiteStr` validator rejects values ending in `/` |
| "Bare" repo (no suites/components/path) uses `/` internally | **VERIFIED** | `_install_sources_apt` sets `suites = ["/"]` when none specified |
| `priority: always` maps to 1000 | **VERIFIED** | `PriorityValue` enum in `package_repository.py` |

#### Correct YAML for a flat local repository

The correct `package-repositories` entry for a flat local directory
(no suites, no components, no subdirectory structure) is:

```yaml
package-repositories:
  - type: apt
    url: file:///WORKSHOP_ROOT/out/deb
    key-id: <40-char Workshop GPG fingerprint>
    priority: always
    # No suites, components, or path keys
```

Omitting `suites`, `components`, and `path` causes `_install_sources_apt`
to use `Suites: /` internally. The local directory must contain a `Packages`
index and a signed `Release` file.

#### Local archive preparation

```bash
cd out/deb/
apt-ftparchive packages . > Packages
apt-ftparchive release . > Release
gpg --batch --yes --armor \
    --default-key workshop@local \
    --detach-sign --output Release.gpg Release
```

The Workshop generates and holds a local GPG key (`workshop@local`).
The public key must be exported and placed in the Snapcraft project
directory as `snap/keys/<last-8-chars-of-fingerprint>.asc` so that
`craft-archives` can install it into the build environment.

#### What requires integration testing

1. **File:// path accessible during `--destructive-mode` build**: When
   Snapcraft runs in destructive mode on the same host, the absolute
   `file://` path should be accessible. This needs one test to confirm.

2. **`apt download` during `kernel_build.sh` resolves from local repo**:
   `kernel_build.sh` calls `apt download linux-image-6.8.0-1080-qcom`
   after `package-repositories` are installed. Whether the `file://` repo
   is active at that point needs verification.

3. **LXD provider access**: `file://` paths on the host are NOT accessible
   in LXD containers by default. For the initial implementation,
   `--destructive-mode` is the only supported Snapcraft provider.

#### Proposed `snapcraft.yaml.template`

```yaml
name: linux-kernel-qcom
build-base: core24
type: kernel
version: "KERNEL_VERSION"
summary: Ubuntu 24.04 kernel for Qualcomm Dragonwing (QCS9075 / SA8775P)
description: |
  Ubuntu 24.04 Noble kernel snap for Qualcomm Dragonwing IQ-9075 EVK.
  SoC: QCS9075 (SA8775P family). Flavour: qcom.
grade: devel
confinement: strict

platforms:
  arm64:
    build-on: [arm64, amd64]
    build-for: [arm64]

package-repositories:
  - type: apt
    url: file://WORKSHOP_ROOT/out/deb
    key-id: GPG_FINGERPRINT
    priority: always

parts:
  kernel:
    plugin: kernel
    kernel-ubuntu-binary-package: true
    kernel-ubuntu-abinumber: "KERNEL_ABI"
    kernel-ubuntu-kconfigflavour: qcom
```

`WORKSHOP_ROOT`, `KERNEL_VERSION`, `KERNEL_ABI`, `GPG_FINGERPRINT` are
substituted by `kernel-build-snap` at build time from `config/workshop.yaml`
and the Workshop's local GPG state.

### Firmware in Kernel Snap

The `linux-image-*-qcom` package does **not** depend on
`linux-firmware-dragonwing`. The kernel snap binary-package repack path
stages whatever firmware the deb includes under `/lib/firmware/`.

**Decision: do not include `linux-firmware-dragonwing` in the initial snap
template.** This is deferred to OQ-4/OQ-5 after Milestone 2 confirms what
firmware, if any, is packaged in the deb.

### `kernel-build-snap`

```
Usage: kernel-build-snap [--config path]

Performs:
  1. Verify out/deb/linux-image-*-qcom*.deb and linux-modules-*-qcom*.deb exist
  2. apt-ftparchive: create Packages and Release in out/deb/
  3. GPG-sign Release → Release.gpg
  4. Export Workshop public key to build/snap/snap/keys/<fingerprint>.asc
  5. Generate build/snap/snapcraft.yaml from template
  6. Run: snapcraft --destructive-mode (from build/snap/)
  7. Move produced *.snap → out/snap/
  8. Write out/snap/metadata/
  9. Validate
```

### Automatic Validation

- Exactly one `*.snap` in `out/snap/`
- `unsquashfs -l out/snap/*.snap | grep -E "kernel\.img|Image\.gz"` succeeds
- `unsquashfs -l out/snap/*.snap | grep modules/` succeeds

---

## Shared Workshop Storage

```
cache/linux-qcom.git/   ← shared bare Git store (neither SDK modifies)
src/kernel/linux-qcom/  ← Kernel SDK exclusive worktree
src/deb/linux-qcom/     ← Debian SDK exclusive worktree
out/deb/                ← written by Debian SDK; read by Snap SDK
out/kernel/             ← written by Kernel SDK; not consumed by other SDKs
config/workshop.yaml    ← read by all SDKs
```

---

## Output Contract

```
out/
├── kernel/
│   ├── image/
│   │   ├── Image.gz
│   │   └── vmlinuz → Image.gz
│   ├── dtbs/
│   │   └── qcs9075-iq-9075-evk.dtb
│   ├── modules/
│   │   └── 6.8.0-1080-qcom/
│   │       └── modules.dep
│   ├── metadata/
│   │   ├── kernel-version    ← "6.8.0-1080-qcom"
│   │   ├── config
│   │   ├── System.map
│   │   └── build-info.yaml
│   └── artifacts.tar.zst     ← optional
│
├── deb/
│   ├── linux-image-6.8.0-1080-qcom_6.8.0-1080.85_arm64.deb
│   ├── linux-modules-6.8.0-1080-qcom_6.8.0-1080.85_arm64.deb
│   ├── linux-headers-6.8.0-1080-qcom_6.8.0-1080.85_arm64.deb
│   ├── linux-qcom-headers-6.8.0-1080_6.8.0-1080.85_all.deb
│   ├── linux-tools-6.8.0-1080-qcom_6.8.0-1080.85_arm64.deb
│   ├── linux-libc-dev-qcom_6.8.0-1080.85_all.deb
│   ├── Packages
│   └── metadata/
│       ├── package-list.txt
│       ├── kernel-version
│       └── flavour
│
└── snap/
    ├── linux-kernel-qcom_6.8.0-1080_arm64.snap
    └── metadata/
        ├── snap-name
        ├── snap-version
        └── build-log.txt
```

---

## Open Questions / Unknowns

### OQ-1: Cross-compile of `debian/rules` on amd64

**Unknown:** Whether `fakeroot debian/rules build-qcom; binary-qcom` on an
amd64 host with `DEB_HOST_ARCH=arm64` completes without errors.

**Why it matters:** CI is typically amd64. Native arm64 build host may not
always be available.

**Source:** One build test.

**Blocks Milestone 2 on amd64 host?** Yes.
**Blocks Milestone 1 (direct kernel build)?** No.

---

### OQ-2: DTB path inside `linux-image-*-qcom.deb`

**Unknown:** Exact install path of `qcs9075-iq-9075-evk.dtb` inside the
image package. Standard paths are `/usr/lib/linux-image-*/` (newer) or
`/lib/firmware/<version>/device-tree/` (older).

**Why it matters:** The Kernel plugin stages DTBs from the package's install
location.

**Source:** `dpkg -c linux-image-6.8.0-1080-qcom_6.8.0-1080.85_arm64.deb`
after a successful Milestone 2 build.

**Blocks Milestone 3?** Potentially requires Snapcraft config adjustment.

---

### OQ-3: Snapcraft local `file://` APT integration (integration test)

**Unknown:** End-to-end: does `kernel-ubuntu-binary-package: true` +
`package-repositories: file://...` + `--destructive-mode` work as designed?

**Sub-items:**
- Is `file://` repo active when `kernel_build.sh` calls `apt download`?
- Does `apt download linux-image-6.8.0-1080-qcom` resolve from local repo
  (given the package does not exist in the standard Ubuntu archive)?
- Does GPG signing work correctly in the Snapcraft build context?

**Blocks Milestone 3?** Yes.

---

### OQ-4: Firmware content of `linux-image-*-qcom.deb`

**Unknown:** Whether the `linux-image-*-qcom.deb` includes any files under
`/lib/firmware/` that would be staged into the kernel snap.

**Why it matters:** If no firmware files are in the deb, the snap's
`firmware/` directory will be empty (or absent). This is acceptable for
a first implementation but should be understood.

**Source:** `dpkg -c linux-image-*-qcom*.deb | grep lib/firmware` after
Milestone 2.

**Blocks Milestone 3?** No.

---

### OQ-5: `linux-firmware-dragonwing` in Ubuntu Noble archive

**Unknown:** Whether `linux-firmware-dragonwing` is in the Noble
main/universe archive or only in a Canonical IoT PPA.

**Source:** `apt-cache show linux-firmware-dragonwing` in a clean Ubuntu
24.04 environment.

**Blocks initial implementation?** No (firmware excluded from first snap).

---

## Implementation Plan

### Milestone 0 — Repository Scaffolding (no build)

Create directory structure, stub commands, configuration.

Tasks:
1. Create `config/workshop.yaml` with IQ-9075 EVK defaults.
2. Create `.gitignore` covering `cache/`, `src/`, `build/`, `out/`.
3. Create stub bin scripts (executable, parse config, print plan, exit 0).
4. Create `sdk/kernel/lib/common.sh` with:
   - `workshop_read_config` (parses YAML via python3 or yq)
   - `workshop_derive_kernelrelease` (implements tag → KERNELRELEASE formula)
   - `workshop_derive_flavour` (reads debian.env if src exists, else from tag)
5. Verify: `kernel-build --config config/workshop.yaml` runs, prints
   derived KERNELRELEASE `6.8.0-1080-qcom`, exits 0.
6. Update README with setup and usage instructions.

---

### Milestone 1 — Kernel SDK: IQ-9075 kernel builds

**Goal:** `kernel-build` produces normalized outputs from `linux-qcom`.

Acceptance criteria:
- `kernel-build` exits 0.
- `file out/kernel/image/Image.gz` → `gzip compressed data`
- `file out/kernel/dtbs/qcs9075-iq-9075-evk.dtb` → `Device Tree Blob`
- `cat out/kernel/modules/6.8.0-1080-qcom/modules.dep` → non-empty
- `cat out/kernel/metadata/kernel-version` → `6.8.0-1080-qcom`

**Do not start Milestone 2 until all criteria pass.**

---

### Milestone 2 — Debian Packaging SDK: Ubuntu kernel .deb packages

**Goal:** `kernel-build-debs` produces complete Ubuntu kernel packages.

During this milestone: resolve OQ-1 (cross-compile) and OQ-2 (DTB path).

Acceptance criteria:
- `kernel-build-debs` exits 0.
- `dpkg-deb --info out/deb/linux-image-*-qcom*.deb` succeeds.
- `dpkg -c out/deb/linux-image-*-qcom*.deb | grep vmlinuz` succeeds.
- `dpkg -c out/deb/linux-modules-*-qcom*.deb | grep modules` succeeds.

**Do not start Milestone 3 until all criteria pass.**

---

### Milestone 3 — Snap Packaging SDK: Ubuntu Core kernel snap

**Goal:** `kernel-build-snap` produces a kernel snap via `plugin: kernel`.

During this milestone: integration test for OQ-3 (local APT + Snapcraft).

Acceptance criteria:
- `kernel-build-snap` exits 0.
- `unsquashfs -l out/snap/*.snap` shows kernel image and modules.
- `snapcraft lint out/snap/*.snap` passes (or no blocking errors).

---

## Design Readiness

| Item | Status | Evidence | Blocks implementation? |
|---|---|---|---|
| `linux-qcom` Noble repository URL | **VERIFIED** | Launchpad API direct inspection | No |
| `linux-qcom` revision for IQ-9075 image | **VERIFIED** | Tag `Ubuntu-qcom-6.8.0-1080.85`, commit `36646c64`, manifest `6.8.0-1080.85` | No |
| SoC identity: QCS9075 / SA8775P | **VERIFIED** | `qcs9075-iq-9075-evk.dts` compatible string | No |
| IQ-9075 primary DTB name | **VERIFIED** | `qcs9075-iq-9075-evk.dts` filename | No |
| Kernel configuration mechanism (annotations) | **VERIFIED** | `stamp-prepare-tree-%` target verbatim; `annotations --export --arch arm64 --flavour qcom` | No |
| `msm_default` impact (OQ-8) | **VERIFIED — RESOLVED (corrected)** | Build test proved `msm_default/` IS required. SAUCE modified `drivers/gpu/drm/Makefile`. `configure.sh` creates it before build. | No — handled in configure.sh |
| KERNELRELEASE derivation | **VERIFIED** | `0-common-vars.mk` formulas traced; `6.8.0-1080-qcom` confirmed from manifest | No |
| `CONFIG_VERSION_SIGNATURE` format | **VERIFIED** | `stamp-prepare-tree-%` sed command | No |
| Direct kernel build (`make Image.gz dtbs modules`) | **VERIFIED** | `arm64.mk` targets; `kmake` definition | No |
| Debian packaging invocation | **VERIFIED** | `clean → build-qcom → binary-qcom → binary-arch-headers` from direct file inspection | No |
| `binary-arch-headers` required | **VERIFIED** | `binary-arch-deps-true += binary-arch-headers` in `2-binary-arch.mk` | No |
| Package output names | **VERIFIED** | `flavour-control.stub` + `vars.qcom` + manifest | No |
| Snapcraft `build-base: core24` (no `base:`) | **VERIFIED** | `iot-field-kernel-snap` template + Snapcraft project model | No |
| `type: kernel` + `build-base: core24` | **VERIFIED** | Same sources | No |
| `kernel-ubuntu-binary-package: true` calls `apt download` | **VERIFIED** | `kernel_build.sh` `build_bin_pkg()` | No |
| `craft-archives` supports `FileUrl` | **VERIFIED** | `PackageRepositoryApt.url: AnyUrl \| FileUrl` | No |
| `key-id` required (40-char GPG fingerprint) | **VERIFIED** | `KeyIdStr` pattern; field is non-optional | No |
| `suites: [/]` in YAML is invalid | **VERIFIED** | `SuiteStr` validator rejects trailing `/` | No |
| Correct bare-repo YAML: omit suites/components/path | **VERIFIED** | `_install_sources_apt` logic | No |
| `priority: always` supported | **VERIFIED** | `PriorityValue` enum | No |
| Local `file://` repo accessible in `--destructive-mode` | **REQUIRES BUILD TEST** | Architecturally expected; untested | Blocks Milestone 3 |
| `apt download` resolves from local repo in `kernel_build.sh` | **REQUIRES BUILD TEST** | Untested end-to-end | Blocks Milestone 3 |
| GPG signing workflow in Snapcraft context | **REQUIRES BUILD TEST** | Mechanism designed; untested | Blocks Milestone 3 |
| Cross-compile `debian/rules` on amd64 | **REQUIRES BUILD TEST** | Architecture supports it; untested | Blocks Milestone 2 on amd64 |
| DTB path inside `linux-image-*-qcom.deb` | **REQUIRES BUILD TEST** | Can only be checked from produced deb | Blocks Milestone 3 DTB staging |
| `linux-firmware-dragonwing` in kernel snap | **OPEN** | Excluded from initial design; not blocking | No |
