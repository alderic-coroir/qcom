#!/usr/bin/bash
# sdk/kernel/lib/stage.sh
# Qualcomm Silicon Workshop — Kernel SDK artifact normalization
#
# Implements the stable out/kernel/ output contract from
# QUALCOMM_WORKSHOP_DESIGN.md.
#
# Normalizes vendor/source-tree paths to stable, downstream-independent paths.
#
# Functions:
#   kernel_stage ROOT FLAVOUR KERNELRELEASE DTBS RESOLVED_SHA

[[ -n "${_KERNEL_STAGE_SH:-}" ]] && return
_KERNEL_STAGE_SH=1

# kernel_stage ROOT FLAVOUR KERNELRELEASE DTBS RESOLVED_SHA
# DTBS is a pipe-separated list of DTB filenames (e.g. "qcs9075-iq-9075-evk.dtb")
kernel_stage() {
    local root="${1}"
    local flavour="${2}"
    local kernelrelease="${3}"
    local dtbs_joined="${4}"      # pipe-separated list
    local resolved_sha="${5}"
    local config_ref_value="${6}"

    local builddir="${root}/build/kernel/build-${flavour}"
    local modules_staging="${root}/build/kernel/modules-staging"
    local out="${root}/out/kernel"

    workshop_log "=== Artifact normalization ==="

    # Create output directories
    mkdir -p "${out}/image" "${out}/dtbs" "${out}/modules" "${out}/metadata"

    # --- Kernel image ---
    workshop_log "Staging kernel image..."
    cp -f "${builddir}/arch/arm64/boot/Image.gz" "${out}/image/Image.gz"
    # Create vmlinuz symlink
    ln -sf "Image.gz" "${out}/image/vmlinuz"
    workshop_log "  out/kernel/image/Image.gz ($(du -h "${out}/image/Image.gz" | cut -f1))"

    # --- DTBs ---
    workshop_log "Staging DTBs..."
    local dtb_errors=()
    IFS='|' read -ra dtb_list <<< "${dtbs_joined}"
    for dtb in "${dtb_list[@]}"; do
        [[ -n "${dtb}" ]] || continue
        # Search in qcom subdirectory first, then recursively
        local dtb_src
        dtb_src="$(find "${builddir}/arch/arm64/boot/dts" -name "${dtb}" -type f 2>/dev/null | head -1)"
        if [[ -z "${dtb_src}" ]]; then
            dtb_errors+=("${dtb}")
            continue
        fi
        cp -f "${dtb_src}" "${out}/dtbs/${dtb}"
        workshop_log "  out/kernel/dtbs/${dtb} ($(du -h "${out}/dtbs/${dtb}" | cut -f1))"
    done

    if [[ ${#dtb_errors[@]} -gt 0 ]]; then
        workshop_fail "DTBs not found after build: ${dtb_errors[*]}\n" \
            "These DTBs were listed in config but were not produced.\n" \
            "Check that the DTS source files exist in the linux-qcom tree."
    fi

    # --- Modules ---
    workshop_log "Staging modules..."
    local mod_src="${modules_staging}/lib/modules/${kernelrelease}"
    [[ -d "${mod_src}" ]] || \
        workshop_fail "Module directory not found: ${mod_src}\n" \
            "modules_install may have used a different KERNELRELEASE."

    rm -rf "${out}/modules/${kernelrelease}"
    cp -a "${mod_src}" "${out}/modules/${kernelrelease}"
    workshop_log "  out/kernel/modules/${kernelrelease}/ ($(du -sh "${out}/modules/${kernelrelease}" | cut -f1))"

    # Remove kernel source/build symlinks from modules dir
    # (these point back into build tree and are not portable)
    rm -f "${out}/modules/${kernelrelease}/source"
    rm -f "${out}/modules/${kernelrelease}/build"

    # --- Metadata ---
    workshop_log "Writing metadata..."

    # kernel-version
    echo "${kernelrelease}" > "${out}/metadata/kernel-version"

    # .config
    cp -f "${builddir}/.config" "${out}/metadata/config"

    # System.map
    cp -f "${builddir}/System.map" "${out}/metadata/System.map"

    # build-info.yaml
    local build_date
    build_date="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    local host_arch
    host_arch="$(uname -m)"
    local compiler_version
    compiler_version="$(${CC} --version 2>/dev/null | head -1 || echo "unknown")"

    # Reconstruct DTB list for YAML
    local dtb_yaml=""
    for dtb in "${dtb_list[@]}"; do
        [[ -n "${dtb}" ]] && dtb_yaml+="  - ${dtb}"$'\n'
    done

    cat > "${out}/metadata/build-info.yaml" <<EOF
# Qualcomm Silicon Workshop — Kernel Build Provenance
build_date: "${build_date}"

silicon:
  vendor: ${CFG_SILICON_VENDOR}
  soc: ${CFG_SILICON_SOC}
  board: ${CFG_SILICON_BOARD}

ubuntu:
  release: ${CFG_UBUNTU_RELEASE}

kernel:
  repository: ${CFG_KERNEL_REPOSITORY}
  ref:
    type: ${CFG_KERNEL_REF_TYPE}
    value: ${config_ref_value}
  resolved_sha: ${resolved_sha}
  kernelrelease: ${kernelrelease}
  flavour: ${flavour}

toolchain:
  target_arch: arm64
  host_arch: ${host_arch}
  cross_compile: "${CROSS_COMPILE}"
  compiler: "${compiler_version}"

device_trees:
${dtb_yaml}
artifacts:
  image: out/kernel/image/Image.gz
  modules: out/kernel/modules/${kernelrelease}/
  dtbs: out/kernel/dtbs/
  metadata: out/kernel/metadata/
EOF

    workshop_log "  out/kernel/metadata/kernel-version: ${kernelrelease}"
    workshop_log "  out/kernel/metadata/build-info.yaml"
    workshop_log "=== Staging complete ==="
}
