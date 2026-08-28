#!/usr/bin/bash
# sdk/kernel/lib/common.sh
# Qualcomm Silicon Workshop — Kernel SDK shared functions
#
# This file is sourced by kernel-build and kernel-clean.
# It provides configuration parsing, version derivation, and shared helpers.
#
# Functions defined here:
#   workshop_find_root        — locate the workshop root directory
#   workshop_read_config      — parse config/workshop.yaml into variables
#   workshop_derive_kernelrelease — compute KERNELRELEASE from the tag
#   workshop_detect_toolchain — determine compiler based on build host arch
#   workshop_check_tools      — verify required tools are present
#   workshop_log              — timestamped log helper
#   workshop_fail             — print error and exit 1
#   workshop_warn             — print warning

set -euo pipefail

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

workshop_log() {
    echo "[kernel-sdk] $*" >&2
}

workshop_warn() {
    echo "[kernel-sdk] WARNING: $*" >&2
}

workshop_fail() {
    echo "[kernel-sdk] ERROR: $*" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Workshop root detection
# ---------------------------------------------------------------------------

# Find the workshop root (directory containing config/workshop.yaml).
# If WORKSHOP_ROOT is already set in the environment, use it.
# Otherwise search upward from the script's location.
workshop_find_root() {
    if [[ -n "${WORKSHOP_ROOT:-}" ]]; then
        echo "${WORKSHOP_ROOT}"
        return
    fi

    # Walk up from the calling script's real path
    local dir
    dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"

    # Walk up to find config/workshop.yaml
    while [[ "${dir}" != "/" ]]; do
        if [[ -f "${dir}/config/workshop.yaml" ]]; then
            echo "${dir}"
            return
        fi
        dir="$(dirname "${dir}")"
    done

    workshop_fail "Cannot locate workshop root (config/workshop.yaml not found). " \
        "Set WORKSHOP_ROOT or run from within the workshop tree."
}

# ---------------------------------------------------------------------------
# Configuration parsing
# ---------------------------------------------------------------------------

# workshop_read_config ROOT
# Parse config/workshop.yaml and export shell variables.
# Sets:
#   CFG_SCHEMA_VERSION   CFG_SILICON_VENDOR   CFG_SILICON_SOC
#   CFG_SILICON_BOARD    CFG_UBUNTU_RELEASE
#   CFG_KERNEL_REPOSITORY  CFG_KERNEL_REF_TYPE  CFG_KERNEL_REF_VALUE
#   CFG_KERNEL_DTBS      (newline-separated list)
#   CFG_TOOLCHAIN_CROSS_COMPILE
workshop_read_config() {
    local root="${1}"
    local config="${root}/config/workshop.yaml"

    [[ -f "${config}" ]] || workshop_fail "Config not found: ${config}"

    # Use python3 + pyyaml for robust YAML parsing
    local parsed
    parsed="$(python3 - "${config}" <<'PYEOF'
import sys, yaml, os

cfg = yaml.safe_load(open(sys.argv[1]))

def get(d, *keys, default=''):
    for k in keys:
        if not isinstance(d, dict) or k not in d:
            return default
        d = d[k]
    return d if d is not None else default

sv = str(get(cfg, 'schema_version', default='1'))
vendor  = str(get(cfg, 'silicon', 'vendor'))
soc     = str(get(cfg, 'silicon', 'soc'))
board   = str(get(cfg, 'silicon', 'board'))
release = str(get(cfg, 'ubuntu', 'release'))
repo    = str(get(cfg, 'kernel', 'repository'))
reftype = str(get(cfg, 'kernel', 'ref', 'type'))
refval  = str(get(cfg, 'kernel', 'ref', 'value'))
dtbs    = get(cfg, 'kernel', 'device_trees', default=[])
cross   = str(get(cfg, 'toolchain', 'cross_compile'))

print(f"CFG_SCHEMA_VERSION={sv}")
print(f"CFG_SILICON_VENDOR={vendor}")
print(f"CFG_SILICON_SOC={soc}")
print(f"CFG_SILICON_BOARD={board}")
print(f"CFG_UBUNTU_RELEASE={release}")
print(f"CFG_KERNEL_REPOSITORY={repo}")
print(f"CFG_KERNEL_REF_TYPE={reftype}")
print(f"CFG_KERNEL_REF_VALUE={refval}")
print(f"CFG_TOOLCHAIN_CROSS_COMPILE={cross}")

# Emit DTB list as a single variable with newlines encoded as |
dtb_joined="|".join(str(d) for d in (dtbs if isinstance(dtbs, list) else [dtbs]))
print(f"CFG_KERNEL_DTBS={dtb_joined}")
PYEOF
)"

    # Export all parsed variables into the current shell
    while IFS='=' read -r key val; do
        [[ -n "${key}" ]] || continue
        export "${key}=${val}"
    done <<< "${parsed}"
}

# ---------------------------------------------------------------------------
# KERNELRELEASE derivation
# ---------------------------------------------------------------------------

# workshop_derive_kernelrelease TAG FLAVOUR
# Compute KERNELRELEASE from a Ubuntu kernel tag and flavour.
#
# Ubuntu kernel tag format: Ubuntu-qcom-<upstream>-<abi>.<upload>
#   e.g. Ubuntu-qcom-6.8.0-1080.85
#
# Derivation (matches debian/rules.d/0-common-vars.mk exactly):
#   version     = strip prefix up to second '-'  → 6.8.0-1080.85
#   revision    = last component after '-'        → 1080.85
#   release     = version minus -revision         → 6.8.0-1080
#   abinum      = first component of revision     → 1080
#   abi_release = release                         → 6.8.0-1080
#   KERNELRELEASE = abi_release-flavour            → 6.8.0-1080-qcom
#
# For branch/commit refs without an abi-encoded name:
#   KERNELRELEASE is set to the flavour-prefixed output of
#   'make kernelversion' — in that case it is approximate.
workshop_derive_kernelrelease() {
    local ref_type="${1}"
    local ref_value="${2}"
    local flavour="${3}"

    if [[ "${ref_type}" == "tag" ]]; then
        # Strip the "Ubuntu-<pkg>-" prefix to get the Debian version string.
        # ${tag#Ubuntu-*-} strips shortest match of "Ubuntu-" + any chars + "-"
        # For "Ubuntu-qcom-6.8.0-1080.85" this correctly yields "6.8.0-1080.85".
        local version
        version="${ref_value#Ubuntu-*-}"  # e.g. 6.8.0-1080.85

        # revision = last component after the final '-' in version
        local revision="${version##*-}"   # e.g. 1080.85

        # release = version without the "-revision" suffix
        # "6.8.0-1080.85" minus "-1080.85" → "6.8.0"
        local release="${version%-${revision}}"  # e.g. 6.8.0

        # abinum = first numeric component of revision (before the first '.')
        local abinum="${revision%%.*}"    # e.g. 1080

        # abi_release = release + "-" + abinum  (from 0-common-vars.mk: abi_release := $(release)-$(abinum))
        local abi_release="${release}-${abinum}"  # e.g. 6.8.0-1080

        echo "${abi_release}-${flavour}"  # e.g. 6.8.0-1080-qcom
    else
        # For branch or commit refs we cannot derive from the tag.
        # Caller must run 'make kernelversion' in the source tree instead.
        echo ""
    fi
}

# workshop_derive_version_info TAG
# Returns: UPSTREAM_VERSION REVISION RELEASE ABINUM UPLOAD
# e.g. for Ubuntu-qcom-6.8.0-1080.85:
#   UPSTREAM_VERSION=6.8.0
#   REVISION=1080.85
#   RELEASE=6.8.0-1080
#   ABINUM=1080
#   UPLOAD=85
workshop_derive_version_info() {
    local tag="${1}"
    # Matching the exact formulas from debian/rules.d/0-common-vars.mk:
    #   version     := dpkg-parsechangelog -S version   e.g. 6.8.0-1080.85
    #   revision    := lastword(version split by '-')    e.g. 1080.85
    #   release     := version without -revision         e.g. 6.8.0
    #   abinum      := firstword(revision split by '.')  e.g. 1080
    #   abi_release := release-abinum                    e.g. 6.8.0-1080
    local version="${tag#Ubuntu-*-}"      # → 6.8.0-1080.85
    local revision="${version##*-}"       # → 1080.85
    local release="${version%-${revision}}" # → 6.8.0  (NOT 6.8.0-1080)
    local abinum="${revision%%.*}"        # → 1080
    local upload="${revision#*.}"         # → 85
    local abi_release="${release}-${abinum}"  # → 6.8.0-1080
    local upstream_version="${release}"   # → 6.8.0 (same as release)

    echo "UPSTREAM_VERSION=${upstream_version}"
    echo "REVISION=${revision}"
    echo "RELEASE=${abi_release}"    # We export abi_release as RELEASE for use in VERSION_SIGNATURE
    echo "ABINUM=${abinum}"
    echo "UPLOAD=${upload}"
}

# ---------------------------------------------------------------------------
# Flavour detection
# ---------------------------------------------------------------------------

# workshop_derive_flavour WORKTREE_PATH
# Read the kernel flavour from debian.env in the worktree.
# Returns the flavour name (e.g. "qcom").
workshop_derive_flavour() {
    local worktree="${1}"
    local debian_env="${worktree}/debian/debian.env"

    [[ -f "${debian_env}" ]] || {
        workshop_fail "debian.env not found at ${debian_env}. " \
            "Is the worktree checked out?"
    }

    local debian_dir
    debian_dir="$(grep '^DEBIAN=' "${debian_env}" | cut -d= -f2)"
    # debian_dir is like "debian.qcom"; flavour is the suffix after the dot
    echo "${debian_dir#debian.}"
}

# ---------------------------------------------------------------------------
# Toolchain detection
# ---------------------------------------------------------------------------

# workshop_detect_toolchain
# Sets KERNEL_ARCH, CROSS_COMPILE, and CC based on the build host.
# Uses config's toolchain.cross_compile if non-empty;
# auto-detects if cross_compile is empty.
workshop_detect_toolchain() {
    local host_arch config_cross
    host_arch="$(uname -m)"
    config_cross="${CFG_TOOLCHAIN_CROSS_COMPILE:-}"

    KERNEL_ARCH="arm64"

    if [[ -n "${config_cross}" ]]; then
        # Use the configured cross-compile prefix
        CROSS_COMPILE="${config_cross}"
    elif [[ "${host_arch}" == "aarch64" ]]; then
        # Native arm64 build — no cross-compiler needed
        CROSS_COMPILE=""
    else
        # Assume amd64 → arm64 cross-compile
        CROSS_COMPILE="aarch64-linux-gnu-"
    fi

    CC="${CROSS_COMPILE}gcc-13"
    HOSTCC="gcc-13"

    workshop_log "Toolchain: ARCH=${KERNEL_ARCH} CC=${CC} CROSS_COMPILE=${CROSS_COMPILE} (host: ${host_arch})"

    export KERNEL_ARCH CROSS_COMPILE CC HOSTCC
}

# ---------------------------------------------------------------------------
# Tool availability checks
# ---------------------------------------------------------------------------

# workshop_check_tools
# Verifies required executables are present before starting a build.
workshop_check_tools() {
    local missing=()

    local required_tools=(
        git make python3 ${CC} file gawk openssl
    )

    # dtc is needed for DTB validation
    required_tools+=(dtc)

    for tool in "${required_tools[@]}"; do
        if ! command -v "${tool}" &>/dev/null; then
            missing+=("${tool}")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        workshop_fail "Required tools not found: ${missing[*]}\n" \
            "Run: sudo apt-get install ${missing[*]}"
    fi

    # Verify python3-yaml is available (needed for config parsing)
    if ! python3 -c "import yaml" 2>/dev/null; then
        workshop_fail "python3-yaml not installed.\nRun: sudo apt-get install python3-yaml"
    fi

    workshop_log "Tool check passed."
}

# ---------------------------------------------------------------------------
# Concurrency
# ---------------------------------------------------------------------------

# workshop_jobs
# Returns the number of parallel jobs: $WORKSHOP_JOBS or nproc.
workshop_jobs() {
    echo "${WORKSHOP_JOBS:-$(nproc)}"
}

# ---------------------------------------------------------------------------
# Config validation
# ---------------------------------------------------------------------------

# workshop_validate_config
# Validate required config fields are present and sensible.
workshop_validate_config() {
    local errors=()

    [[ -n "${CFG_SCHEMA_VERSION:-}" ]] || errors+=("schema_version is missing")
    [[ -n "${CFG_SILICON_VENDOR:-}" ]] || errors+=("silicon.vendor is missing")
    [[ -n "${CFG_SILICON_SOC:-}" ]] || errors+=("silicon.soc is missing")
    [[ -n "${CFG_SILICON_BOARD:-}" ]] || errors+=("silicon.board is missing")
    [[ -n "${CFG_UBUNTU_RELEASE:-}" ]] || errors+=("ubuntu.release is missing")
    [[ -n "${CFG_KERNEL_REPOSITORY:-}" ]] || errors+=("kernel.repository is missing")
    [[ -n "${CFG_KERNEL_REF_TYPE:-}" ]] || errors+=("kernel.ref.type is missing")
    [[ -n "${CFG_KERNEL_REF_VALUE:-}" ]] || errors+=("kernel.ref.value is missing")
    [[ -n "${CFG_KERNEL_DTBS:-}" ]] || errors+=("kernel.device_trees is empty")

    local valid_ref_types=("tag" "branch" "commit")
    local valid=false
    for t in "${valid_ref_types[@]}"; do
        [[ "${CFG_KERNEL_REF_TYPE}" == "${t}" ]] && valid=true && break
    done
    ${valid} || errors+=("kernel.ref.type must be one of: ${valid_ref_types[*]}")

    if [[ ${#errors[@]} -gt 0 ]]; then
        workshop_fail "Configuration validation failed:\n$(printf '  - %s\n' "${errors[@]}")"
    fi

    workshop_log "Configuration valid: ${CFG_SILICON_VENDOR}/${CFG_SILICON_SOC}/${CFG_SILICON_BOARD} ubuntu=${CFG_UBUNTU_RELEASE} ref=${CFG_KERNEL_REF_TYPE}:${CFG_KERNEL_REF_VALUE}"
}
