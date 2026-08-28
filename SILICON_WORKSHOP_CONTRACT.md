# Silicon Workshop Contract

**Version:** 0.2  
**Status:** Draft  
**Purpose:** Common architecture and implementation contract for Canonical Silicon Workshops.

## 1. Purpose

A **Silicon Workshop** provides a reproducible development environment for building and packaging an Ubuntu kernel for a supported silicon family.

A Silicon Workshop MUST support two operating modes:

- **Reference EVK mode:** without project-specific customization, the Workshop MUST build a valid kernel for the supported reference EVK.
- **BSP-specialized mode:** a future external agent MAY customize declarative configuration from BSP analysis. Normal specialization SHOULD NOT require changes to SDK implementation code.

The checked-in EVK configuration is both the known-good baseline and the reference example for future agent specialization.

## 2. Fundamental design rules

### 2.1 Exactly three functional SDKs

Every Silicon Workshop MUST contain exactly three functional SDKs:

```text
Silicon Workshop
│
├── Kernel SDK
├── Debian Packaging SDK
└── Snap Packaging SDK
```

No additional functional kernel-build or kernel-packaging SDK SHOULD be introduced. Supporting files, shared code, configuration, patches, templates, documentation and tests MAY live outside the SDKs.

### 2.2 Minimal public command surface

Each SDK SHOULD expose as few public commands as practical. Commands represent complete useful workflows rather than implementation steps.

Target public interface:

```text
Kernel SDK:
    kernel-build
    kernel-clean

Debian Packaging SDK:
    kernel-build-debs

Snap Packaging SDK:
    kernel-build-snap
```

Additional public commands MUST have a concrete user-facing justification. Internal decomposition into scripts, functions and libraries is encouraged.

### 2.3 EVK works by default

A newly checked-out Workshop MUST contain a complete default configuration for a supported reference EVK.

A user SHOULD be able to follow this path without BSP-agent customization:

```text
clone repository
      ↓
launch Workshop
      ↓
run kernel-build
```

The default configuration MUST contain enough information to reproduce the EVK build, including where applicable the SoC, board, Ubuntu release, kernel source/revision, toolchain, kernel configuration, DTBs, vendor dependencies and build requirements.

### 2.4 Configuration is the customization API

The future agent configures **what must be built**. The SDK implementation defines **how it is built**.

Project-specific values SHOULD be declarative rather than hard-coded into SDK scripts. Normal BSP specialization SHOULD NOT require rewriting SDK code.

## 3. System boundaries

```text
BSP Analysis
     │
     ▼
BSP Agent
     │ specializes
     ▼
Project Configuration
     │
     ▼
Silicon Workshop
     │
     ├─────────────┬──────────────┐
     ▼             ▼              ▼
 Kernel SDK    Debian SDK      Snap SDK
```

### 3.1 BSP analysis

BSP analysis is external to the Silicon Workshop. It is expected eventually to provide information such as:

- SoC family
- kernel repository
- kernel branch or tag
- toolchain specifications
- kernel configuration
- device trees
- vendor dependencies
- build requirements

The precise BSP-analysis schema is outside this contract. The Workshop MUST NOT perform BSP analysis.

### 3.2 Agent

The future agent maps BSP analysis to a supported Silicon Workshop and specializes project configuration. Expected customization includes:

- Ubuntu OS release
- kernel repository
- kernel branch or tag
- patchsets
- out-of-tree drivers
- PPA channels
- kernel/build configuration
- device trees
- environment configuration

The agent SHOULD change declarative data. It SHOULD NOT normally rewrite SDK implementation, create vendor build scripts, add SDKs or bypass Ubuntu packaging mechanisms.

### 3.3 Silicon Workshop

The Silicon Workshop owns reusable silicon-specific implementation knowledge, including vendor build tools, toolchains, required utilities, filesystem layout, silicon-specific build mechanics, helper implementation, diagnostics, validation, Ubuntu Debian packaging integration and Ubuntu Core kernel-snap integration.

## 4. Configuration model

The final project configuration schema is intentionally not frozen in this version. A future configuration MAY look conceptually like:

```yaml
silicon:
  vendor: qualcomm
  family: <soc-family>
  board: <reference-evk>

ubuntu:
  release: noble
  target: classic  # or core

kernel:
  repository: <repository>
  ref:
    type: branch
    value: <branch>
  config:
    type: defconfig
    value: <defconfig>
  device_trees:
    - <board.dtb>

toolchain:
  type: llvm

patches: []

drivers:
  out_of_tree: []

archives:
  ppas: []
```

This example is illustrative only. The BSP-analysis schema and the Workshop project schema MUST be allowed to evolve independently.

## 5. Kernel SDK contract

The Kernel SDK owns the silicon-specific mechanics needed to prepare and build the Linux kernel.

It MUST produce, as applicable:

- kernel image
- kernel modules
- requested device trees
- build metadata
- optionally, a raw-artifact archive

### 5.1 Required logical workflow

`kernel-build` SHOULD perform the complete workflow:

```text
read configuration
       ↓
validate configuration/environment
       ↓
obtain kernel source
       ↓
checkout configured revision
       ↓
apply configured patches
       ↓
integrate configured out-of-tree components
       ↓
prepare kernel configuration
       ↓
build kernel
       ↓
build DTBs
       ↓
build modules
       ↓
stage normalized artifacts
       ↓
validate outputs
```

These stages SHOULD normally remain implementation details rather than public commands.

### 5.2 Public commands

#### `kernel-build`

MUST perform the complete kernel build required to obtain usable artifacts and MUST return a non-zero exit status when the requested output cannot be built or validated.

#### `kernel-clean`

MUST remove generated kernel build state sufficiently to allow a clean rebuild. It SHOULD NOT delete project configuration, externally supplied sources, patches, credentials or user-owned material unless explicitly documented.

## 6. Kernel output contract

Vendor-specific source-tree paths MUST be normalized before exposing output to downstream SDKs.

Conceptually:

```text
out/
└── kernel/
    ├── image/
    ├── dtbs/
    ├── modules/
    ├── metadata/
    └── artifacts.tar.*
```

The exact final layout will be standardized during implementation. The Debian Packaging SDK MUST NOT need to discover arbitrary vendor-specific paths such as `arch/arm64/boot/Image` or `arch/arm64/boot/dts/qcom/...`.

## 7. Debian Packaging SDK contract

The Debian Packaging SDK is responsible for producing Ubuntu kernel Debian packages.

Its intended public interface is:

```text
kernel-build-debs
```

It MUST:

- consume the Workshop project configuration;
- use the kernel source/build state appropriate for Ubuntu kernel packaging;
- produce valid `.deb` packages;
- write outputs to a stable location;
- validate the produced packages;
- avoid duplicating silicon-specific build mechanics already owned by the Kernel SDK.

Conceptual output:

```text
out/
└── deb/
    ├── *.deb
    └── metadata/
```

The Debian SDK is the authoritative packaging layer for Ubuntu Classic kernel deliverables.

## 8. Snap Packaging SDK contract

The Snap Packaging SDK is responsible for producing an Ubuntu Core **kernel snap**.

Its intended public interface is:

```text
kernel-build-snap
```

### 8.1 HARD REQUIREMENT: Snapcraft Kernel plugin

The kernel snap MUST be created using the **Snapcraft Kernel plugin**.

The Snapcraft project MUST contain a kernel part using:

```yaml
parts:
  kernel:
    plugin: kernel
```

The Snap SDK MUST NOT replace the Snapcraft Kernel plugin with custom shell logic that manually assembles a kernel snap.

The Snapcraft project MAY contain other parts where necessary for initrd, firmware, device-specific content or supporting integration, but the kernel itself MUST be handled through `plugin: kernel`.

When Ubuntu Debian kernel packages are used as the input path, the implementation MUST use a Snapcraft-Kernel-plugin-supported Debian/binary-package workflow rather than bypassing the plugin.

The precise plugin keys MAY evolve with Snapcraft. Implementations MUST follow the supported Snapcraft version used by the Workshop.

### 8.2 Debian packages are the packaging boundary

The intended architecture is:

```text
Kernel SDK
    │
    ▼
kernel source/build state
    │
    ▼
Debian Packaging SDK
    │
    ▼
Ubuntu kernel Debian packages
    │
    ▼
Snap Packaging SDK
    │
    ▼
Snapcraft Kernel plugin
    │
    ▼
Ubuntu Core kernel snap
```

The Snap SDK MUST NOT introduce an unrelated parallel kernel compilation/packaging path.

If consuming locally produced Debian packages requires a local archive, staging mechanism or another supported Snapcraft integration, that integration SHOULD be implemented inside the Snap SDK while retaining the Kernel plugin as the kernel-snap builder.

### 8.3 Output

Conceptually:

```text
out/
└── snap/
    ├── *.snap
    └── metadata/
```

The produced snap MUST be validated before `kernel-build-snap` succeeds.

## 9. Dependency orchestration

Higher-level operations SHOULD satisfy prerequisites automatically where practical.

```text
kernel-build
    ↓
raw kernel artifacts
```

```text
kernel-build-debs
    ↓
ensure required kernel state
    ↓
build Debian packages
```

```text
kernel-build-snap
    ↓
ensure required kernel state
    ↓
ensure Debian packages
    ↓
run Snapcraft with Kernel plugin
    ↓
produce kernel snap
```

The user SHOULD NOT need to manually understand or execute every intermediate stage. Valid existing outputs SHOULD be reused where practical.

## 10. Ubuntu targets

### Ubuntu Classic

```text
Project configuration
      ↓
Kernel SDK
      ↓
Debian Packaging SDK
      ↓
Ubuntu kernel .deb packages
```

### Ubuntu Core

```text
Project configuration
      ↓
Kernel SDK
      ↓
Debian Packaging SDK
      ↓
Ubuntu kernel .deb packages
      ↓
Snap Packaging SDK
      ↓
Snapcraft Kernel plugin
      ↓
Ubuntu Core kernel snap
```

Raw artifacts are development/integration outputs and do not replace Ubuntu packaging.

## 11. Validation

Successful execution MUST mean more than an underlying build command returning zero.

### Kernel SDK validation

Where applicable, validate that:

- the kernel image exists and is non-empty;
- requested DTBs exist and are non-empty;
- modules were produced;
- output architecture is correct;
- required build metadata can be determined.

### Debian SDK validation

Validate that:

- expected `.deb` files exist;
- packages are structurally readable;
- package metadata corresponds to the requested build;
- required image/modules packages are present for the chosen packaging model.

### Snap SDK validation

Validate that:

- the snap exists;
- Snapcraft completed successfully;
- the snap is of kernel type;
- expected kernel/module/initrd/device-tree content exists where required;
- metadata corresponds to the configured target.

Validation SHOULD occur automatically inside the main workflow commands.

## 12. Diagnostics

Dedicated diagnostic commands are NOT required by this contract. Main workflow failures SHOULD expose actionable diagnostics for common failures such as missing dependencies/toolchains, invalid configuration, repository/revision problems, patch failures, kernel/config/DTB/module failures, Debian packaging failures, missing package dependencies, Snapcraft failures and Kernel-plugin configuration failures.

Additional diagnostic commands MAY be added only when a concrete workflow justifies them.

## 13. Reproducibility

A Silicon Workshop SHOULD explicitly define or pin important inputs where practical, including:

- Ubuntu release
- kernel revision
- toolchain
- vendor build tools
- Debian packaging dependencies
- Snapcraft version/channel where compatibility requires it

Given the same configuration and available upstream inputs, the Workshop SHOULD provide a reproducible build environment.

## 14. Credentials and private resources

Configuration MAY refer to private Git repositories, private PPAs or restricted vendor resources. Credentials MUST NOT be committed into Workshop source or generated project configuration.

The future agent MUST NOT embed credentials in generated configuration. Authentication MUST be supplied through an external supported mechanism.

## 15. EVK acceptance requirement

A Silicon Workshop is not complete solely because its SDK definitions build syntactically.

The checked-in default configuration MUST represent a real supported EVK and demonstrate at minimum:

```text
default configuration
       ↓
kernel-build
       ↓
valid EVK kernel / modules / DTBs
       ↓
kernel-build-debs
       ↓
valid Ubuntu kernel Debian packages
       ↓
kernel-build-snap
       ↓
Snapcraft Kernel plugin
       ↓
valid Ubuntu Core kernel snap
```

Where hardware is available, the produced kernel SHOULD also be demonstrated to boot successfully on the reference EVK.

## 16. Agent compatibility

The future BSP agent SHOULD be able to operate approximately as follows:

```text
BSP Analysis
     ↓
identify silicon
     ↓
select Silicon Workshop
     ↓
inspect supported/default configuration
     ↓
specialize declarative project configuration
     ↓
validate configuration
     ↓
handover Workshop to user
```

The agent SHOULD NOT need knowledge of internal SDK implementation details.

## 17. Out of scope for v0.x

The following are intentionally outside this contract for now:

- final BSP-analysis schema
- final project-configuration schema
- BSP-agent implementation or prompting
- automated Workshop discovery/catalogue protocol
- CI/CD
- PPA publication
- Snap Store publication
- signing
- Secure Boot
- Ubuntu Core gadget generation
- model assertion generation
- complete Ubuntu image generation
- bootloader/firmware building
- flashing
- provisioning

These concerns MAY receive separate contracts later.

## 18. Acceptance criteria

A Silicon Workshop satisfies this contract when:

1. It contains exactly three functional SDKs: Kernel, Debian Packaging and Snap Packaging.
2. It contains a complete default configuration for a real supported EVK.
3. `kernel-build` works with the default configuration without agent customization.
4. Kernel image, requested DTBs and modules are produced and validated.
5. `kernel-build-debs` produces valid Ubuntu kernel Debian packages.
6. `kernel-build-snap` produces a valid Ubuntu Core kernel snap.
7. The kernel snap is built using Snapcraft's `plugin: kernel`.
8. The Snap SDK uses the Debian kernel packaging path and does not create an independent hand-written kernel-snap path.
9. Build outputs have stable locations independent of vendor source-tree layout.
10. Project/BSP-specific parameters are declarative rather than hard-coded into executable SDK implementation.
11. Normal BSP specialization does not require SDK source changes.
12. Validation is integrated into each principal build operation.
13. Credentials are never stored in Workshop or generated project configuration.
14. The public command surface remains intentionally minimal.
15. Hardware boot validation is performed on the reference EVK where hardware is available.

## 19. Authoritative implementation guidance

When Workshop, SDKcraft, Snapcraft or Ubuntu kernel-packaging behavior may have changed, contributors and coding agents MUST consult current official Canonical documentation/source rather than relying on historical examples.

For the Snap SDK in particular, check the current Snapcraft Kernel plugin documentation before implementation:

https://documentation.ubuntu.com/snapcraft/latest/reference/plugins/kernel_plugin/

The stable architecture requirement is:

> **The Ubuntu Core kernel snap is built through Snapcraft's Kernel plugin, not through a custom replacement implementation.**
