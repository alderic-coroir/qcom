# Qualcomm Silicon Workshop

Reproducible build environment for the Ubuntu 24.04 Noble `linux-qcom` kernel
targeting the **Qualcomm Dragonwing IQ-9075 EVK** (QCS9075 / SA8775P).

## Target platform

| Field | Value |
|---|---|
| Platform | Qualcomm Dragonwing™ IQ-9075 Evaluation Kit |
| SoC | QCS9075 (SA8775P family) |
| Architecture | arm64 (AArch64) |
| Ubuntu release | **24.04 LTS (Noble)** only |
| Kernel source | `linux-qcom` Noble on Launchpad |
| Default reference tag | `Ubuntu-qcom-6.8.0-1080.85` |
| Default commit | `36646c64159f94636a17f59b949863ba3702ebab` |

> **Ubuntu 24.04 only.** This Workshop does not support other Ubuntu releases.

## Architecture

This Workshop contains exactly three functional SDK definitions:

| SDK | Status | Public commands |
|---|---|---|
| Kernel SDK | **IMPLEMENTED** (Milestone 1) | `kernel-build`, `kernel-clean` |
| Debian Packaging SDK | Placeholder (Milestone 2) | `kernel-build-debs` (not yet functional) |
| Snap Packaging SDK | Placeholder (Milestone 3) | `kernel-build-snap` (not yet functional) |

## Prerequisites

On an Ubuntu 24.04 host:

```bash
sudo apt-get install \
    git make python3 python3-yaml \
    bc bison flex libelf-dev libssl-dev cpio \
    gcc-13 binutils-aarch64-linux-gnu gcc-13-aarch64-linux-gnu \
    device-tree-compiler dwarves fakeroot
```

## Quick start

### Using Workshop (recommended)

```bash
# First-time setup (launches the Workshop environment)
workshop launch qcom-kernel

# Build the IQ-9075 kernel
workshop run kernel-build

# Clean build state (keep source cache)
workshop run kernel-clean

# Full reset (including worktree, keeping bare clone)
workshop run kernel-clean -- --all
```

### Direct script invocation (no Workshop required)

```bash
# From the repository root:
bash sdk/kernel/bin/kernel-build
bash sdk/kernel/bin/kernel-clean
bash sdk/kernel/bin/kernel-clean --all
```

## Configuration

The default configuration is in `config/workshop.yaml`. It targets the
IQ-9075 EVK at the known-good Ubuntu 24.04 reference revision. The Workshop
works without modification for the default reference build.

To build a different revision, change `kernel.ref` in `config/workshop.yaml`:

```yaml
kernel:
  ref:
    type: tag          # or: branch, commit
    value: Ubuntu-qcom-6.8.0-1080.85
```

For native arm64 builds, set:

```yaml
toolchain:
  cross_compile: ""   # empty = native
```

## Output

After a successful `kernel-build`:

```
out/kernel/
├── image/
│   ├── Image.gz          — compressed kernel image
│   └── vmlinuz           — symlink → Image.gz
├── dtbs/
│   └── qcs9075-iq-9075-evk.dtb   — IQ-9075 EVK device tree
├── modules/
│   └── 6.8.0-1080-qcom/  — kernel modules tree
└── metadata/
    ├── kernel-version    — "6.8.0-1080-qcom"
    ├── config            — .config used for the build
    ├── System.map        — kernel symbol map
    └── build-info.yaml   — full build provenance
```

All downstream tools should consume from `out/kernel/` only.
Do not reference paths inside `src/kernel/linux-qcom/` or `build/kernel/`.

## Source management

The Workshop uses an isolated source model:

```
cache/linux-qcom.git/       — shared bare Git clone (never modified)
src/kernel/linux-qcom/      — Kernel SDK worktree
src/deb/linux-qcom/         — Debian SDK worktree (future Milestone 2)
```

The bare clone is populated on the first run and reused on subsequent runs.
The Kernel SDK and Debian SDK use independent worktrees to prevent state
corruption.

## kernel-clean behavior

| Command | What is removed | What is kept |
|---|---|---|
| `kernel-clean` | `build/kernel/` `out/kernel/` | Everything else |
| `kernel-clean --all` | + `src/kernel/linux-qcom/` | `cache/linux-qcom.git/` and all config |

The shared Git cache is never removed automatically. To remove it:
```bash
rm -rf cache/linux-qcom.git
```

## Milestone status

| Milestone | Description | Status |
|---|---|---|
| 0 | Scaffolding: Workshop structure, 3 SDKs, config | **COMPLETE** |
| 1 | Kernel SDK: `kernel-build` / `kernel-clean` | **COMPLETE** |
| 2 | Debian Packaging SDK: `kernel-build-debs` | Not started |
| 3 | Snap Packaging SDK: `kernel-build-snap` | Not started |

## Documentation

| File | Purpose |
|---|---|
| `SILICON_WORKSHOP_CONTRACT.md` | Cross-silicon architecture contract |
| `QUALCOMM_WORKSHOP_DESIGN.md` | Qualcomm-specific design and research |
| `CLAUDE.md` | Coding-agent implementation instructions |
