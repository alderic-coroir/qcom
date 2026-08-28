#!/usr/bin/bash
# sdk/kernel/lib/build.sh
# Qualcomm Silicon Workshop — Kernel SDK build orchestration
#
# Implements the verified kernel build sequence from QUALCOMM_WORKSHOP_DESIGN.md.
# Runs out-of-tree make for: Image.gz, dtbs, modules, modules_install.
#
# Functions:
#   kernel_build ROOT FLAVOUR KERNELRELEASE JOBS

[[ -n "${_KERNEL_BUILD_SH:-}" ]] && return
_KERNEL_BUILD_SH=1

# kernel_build ROOT FLAVOUR KERNELRELEASE JOBS
# Builds the kernel image, DTBs, modules, and installs modules to staging.
kernel_build() {
    local root="${1}"
    local flavour="${2}"
    local kernelrelease="${3}"
    local jobs="${4:-$(nproc)}"

    local src="${root}/src/kernel/linux-qcom"
    local builddir="${root}/build/kernel/build-${flavour}"
    local modules_staging="${root}/build/kernel/modules-staging"

    [[ -f "${builddir}/.config" ]] || \
        workshop_fail "No .config found at ${builddir}/.config. Run configure step first."

    workshop_log "=== Kernel build ==="
    workshop_log "Source:       ${src}"
    workshop_log "Build dir:    ${builddir}"
    workshop_log "ARCH:         ${KERNEL_ARCH}"
    workshop_log "CROSS:        ${CROSS_COMPILE}"
    workshop_log "CC:           ${CC}"
    workshop_log "KERNELRELEASE: ${kernelrelease}"
    workshop_log "Jobs:         ${jobs}"

    # Common make arguments
    local make_args=(
        -C "${src}"
        O="${builddir}"
        ARCH="${KERNEL_ARCH}"
        CROSS_COMPILE="${CROSS_COMPILE}"
        CC="${CC}"
        HOSTCC="${HOSTCC}"
        KERNELRELEASE="${kernelrelease}"
        -j"${jobs}"
    )

    # Step 1: Build kernel image (Image.gz for arm64)
    workshop_log "Building Image.gz..."
    make "${make_args[@]}" Image.gz \
        2>&1 | tee "${root}/build/kernel/build-image.log" | \
        grep -E "^(LD|CC|AR|OBJCOPY|  HOSTCC|  GEN|  CHK|  UPD|  GZIP|  WRAP|error:|warning:|make\[)" | \
        sed 's/^/[build] /' >&2 || \
        workshop_fail "Image.gz build failed. See ${root}/build/kernel/build-image.log"

    [[ -f "${builddir}/arch/arm64/boot/Image.gz" ]] || \
        workshop_fail "Image.gz not found after build."
    workshop_log "Image.gz built: $(du -h "${builddir}/arch/arm64/boot/Image.gz" | cut -f1)"

    # Step 2: Build DTBs
    workshop_log "Building DTBs..."
    make "${make_args[@]}" dtbs \
        2>&1 | tee "${root}/build/kernel/build-dtbs.log" | \
        grep -E "^(  DTC|error:|make\[)" | sed 's/^/[dtbs] /' >&2 || \
        workshop_fail "DTBs build failed. See ${root}/build/kernel/build-dtbs.log"
    workshop_log "DTBs built."

    # Step 3: Build modules
    workshop_log "Building modules..."
    make "${make_args[@]}" modules \
        2>&1 | tee "${root}/build/kernel/build-modules.log" | \
        grep -E "^(  CC|  LD|error:|make\[)" | sed 's/^/[modules] /' >&2 || \
        workshop_fail "Modules build failed. See ${root}/build/kernel/build-modules.log"
    workshop_log "Modules built."

    # Step 4: Install modules to staging area
    mkdir -p "${modules_staging}"
    workshop_log "Installing modules to ${modules_staging}..."
    make -C "${src}" \
        O="${builddir}" \
        ARCH="${KERNEL_ARCH}" \
        CROSS_COMPILE="${CROSS_COMPILE}" \
        CC="${CC}" \
        INSTALL_MOD_PATH="${modules_staging}" \
        KERNELRELEASE="${kernelrelease}" \
        modules_install \
        2>&1 | grep -E "^(  INSTALL|DEPMOD|error:)" | sed 's/^/[mod-install] /' >&2 || \
        workshop_fail "modules_install failed."

    workshop_log "Modules installed to ${modules_staging}/lib/modules/${kernelrelease}/"
    workshop_log "=== Build complete ==="
}
