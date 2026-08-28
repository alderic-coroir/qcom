# CLAUDE.md

## Project purpose

This repository implements a **Canonical Silicon Workshop** for building and packaging Ubuntu kernels for a supported silicon family.

The wider future architecture contains a BSP-analysis system and an agent that will select a Silicon Workshop and specialize its declarative project configuration. Those systems are external to this repository.

This repository implements the Silicon Workshop itself.

## Mandatory reading

Before designing, modifying or reviewing this repository, read:

1. [`SILICON_WORKSHOP_CONTRACT.md`](./SILICON_WORKSHOP_CONTRACT.md)

Treat that document as the architecture contract.

If repository implementation conflicts with the contract, do not silently preserve the conflict. Explain it and propose a contract-compliant change.

## Hard architectural requirements

### Exactly three SDKs

The Workshop contains exactly three functional SDKs:

1. Kernel SDK
2. Debian Packaging SDK
3. Snap Packaging SDK

Do not introduce additional functional SDKs without an explicit architecture change approved by the project owners.

### Keep commands minimal

Prefer complete workflows over many small public commands.

Target public interface:

```text
kernel-build
kernel-clean
kernel-build-debs
kernel-build-snap
```

Do not create public fetch/configure/dtb/modules/validate commands unless a concrete user requirement cannot be handled cleanly inside the main workflows. Internal decomposition is encouraged.

### Reference EVK works by default

The checked-in configuration MUST describe a real supported reference EVK.

The default Workshop must work without an agent first modifying its configuration.

The EVK is the known-good baseline for the silicon implementation.

### Agent changes configuration, not implementation

Future BSP specialization should normally happen by modifying declarative project configuration.

Do not hard-code customer/project BSP information into SDK scripts.

Do not design the SDK so that the future agent must rewrite build scripts for normal BSP adaptation.

## Kernel SDK

The Kernel SDK owns silicon-specific kernel-build mechanics.

Main operation:

```text
kernel-build
```

It should perform the complete required workflow:

```text
configuration/environment validation
→ source acquisition
→ revision selection
→ patch application
→ optional out-of-tree integration
→ kernel configuration
→ kernel build
→ DTB build
→ modules build
→ normalized artifact staging
→ validation
```

Do not expose each stage as a public command by default.

The Kernel SDK must normalize vendor source-tree outputs into stable Workshop output locations for downstream SDKs.

## Debian Packaging SDK

The Debian Packaging SDK produces Ubuntu kernel Debian packages.

Main operation:

```text
kernel-build-debs
```

It consumes the project configuration and appropriate kernel source/build state. It must use proper Ubuntu/Debian kernel packaging mechanisms and must not unnecessarily duplicate silicon-specific kernel-build logic.

## Snap Packaging SDK

The Snap Packaging SDK produces the Ubuntu Core kernel snap.

Main operation:

```text
kernel-build-snap
```

### NON-NEGOTIABLE: use the Snapcraft Kernel plugin

The kernel snap MUST be created using Snapcraft's Kernel plugin.

The Snapcraft project MUST contain a kernel part using:

```yaml
parts:
  kernel:
    plugin: kernel
```

Do NOT implement a custom replacement that manually assembles the kernel snap.

The required architecture is:

```text
Kernel SDK
→ Debian Packaging SDK
→ Ubuntu kernel Debian packages
→ Snap Packaging SDK
→ Snapcraft Kernel plugin
→ Ubuntu Core kernel snap
```

Use the Snapcraft Kernel plugin's supported Debian/binary-package capabilities where appropriate.

If consuming locally produced Debian packages requires a local archive, staging mechanism or another supported integration, implement that integration rather than bypassing the Kernel plugin.

Snapcraft evolves. Always verify current plugin behavior before implementing or changing this area.

Official documentation:

https://documentation.ubuntu.com/snapcraft/latest/reference/plugins/kernel_plugin/

## Avoid historical architecture assumptions

Do not copy architecture from previous prototypes unless a specific implementation detail is independently justified by this project's requirements.

This project starts from the architecture defined in `SILICON_WORKSHOP_CONTRACT.md`.

Prefer the simplest implementation that satisfies the contract.

## Configuration

The final project-configuration schema has not yet been frozen.

When implementing configuration:

- keep it declarative;
- keep defaults suitable for the reference EVK;
- separate project-specific values from SDK implementation;
- make validation explicit;
- avoid unnecessary fields;
- do not bind the implementation directly to the external BSP-analysis schema.

The BSP-analysis format belongs to another system and may evolve independently.

## Validation

A successful command means its output has been validated, not merely that an underlying build command returned zero.

Build commands should fail clearly when required output is missing or invalid.

Prefer integrated validation over extra user-facing validation commands.

## Credentials

Never commit or generate credentials.

Do not place credentials in project configuration.

Private Git, PPA or vendor-resource authentication must be supplied externally using supported mechanisms.

## Scope discipline

Unless explicitly requested, do not expand the project into:

- BSP analysis
- BSP-agent implementation
- bootloader/firmware builds
- complete OS image construction
- gadget snap generation
- model assertion generation
- flashing
- provisioning
- publication systems
- signing infrastructure
- Secure Boot infrastructure

The immediate goal is the three-SDK kernel Workshop.

## Development approach

For a new silicon Workshop:

1. establish the real reference-EVK build procedure;
2. document required kernel source, revision, toolchain, configuration and DTBs;
3. make `kernel-build` reproduce that build;
4. normalize resulting artifacts;
5. implement Ubuntu Debian packaging;
6. implement the kernel snap using Snapcraft `plugin: kernel` and the Debian packaging path;
7. validate all three outputs;
8. only then generalize configuration for future BSP-agent specialization.

Do not prematurely build agent abstractions before the default EVK path works end to end.

## Source of truth

For architecture:

- `SILICON_WORKSHOP_CONTRACT.md`

For rapidly evolving Canonical tooling:

- current official Canonical documentation;
- current official Canonical source repositories.

Do not rely on stale examples when current behavior can be verified from official sources.
