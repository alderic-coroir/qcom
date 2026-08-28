#!/usr/bin/bash
# sdk/kernel/lib/validate.sh
# Qualcomm Silicon Workshop — Kernel SDK output validation
#
# Validates the out/kernel/ artifacts after staging.
# All 10 checks from the contract in QUALCOMM_WORKSHOP_DESIGN.md are
# implemented here.
#
# Functions:
#   kernel_validate ROOT KERNELRELEASE DTBS RESOLVED_SHA

[[ -n "${_KERNEL_VALIDATE_SH:-}" ]] && return
_KERNEL_VALIDATE_SH=1

# kernel_validate ROOT KERNELRELEASE DTBS_JOINED RESOLVED_SHA EXPECTED_SHA
kernel_validate() {
    local root="${1}"
    local kernelrelease="${2}"
    local dtbs_joined="${3}"
    local resolved_sha="${4}"
    local expected_sha="${5:-}"

    local out="${root}/out/kernel"
    local errors=()

    workshop_log "=== Output validation ==="

    # 1. Image.gz exists and is non-empty
    if [[ ! -s "${out}/image/Image.gz" ]]; then
        errors+=("CHECK 1 FAILED: out/kernel/image/Image.gz missing or empty")
    fi

    # 2. Image.gz is a valid gzip stream
    if [[ -f "${out}/image/Image.gz" ]]; then
        if ! gzip -t "${out}/image/Image.gz" 2>/dev/null; then
            errors+=("CHECK 2 FAILED: out/kernel/image/Image.gz is not a valid gzip stream")
        else
            workshop_log "  [PASS] Image.gz is a valid gzip stream"
        fi
    fi

    # 3. vmlinuz symlink exists
    if [[ ! -L "${out}/image/vmlinuz" ]]; then
        errors+=("CHECK 3 FAILED: out/kernel/image/vmlinuz symlink missing")
    else
        workshop_log "  [PASS] vmlinuz symlink present"
    fi

    # 4. All configured DTBs exist
    IFS='|' read -ra dtb_list <<< "${dtbs_joined}"
    for dtb in "${dtb_list[@]}"; do
        [[ -n "${dtb}" ]] || continue
        if [[ ! -s "${out}/dtbs/${dtb}" ]]; then
            errors+=("CHECK 4 FAILED: out/kernel/dtbs/${dtb} missing or empty")
        else
            workshop_log "  [PASS] DTB present: ${dtb}"
        fi
    done

    # 5. DTBs are valid FDT blobs
    for dtb in "${dtb_list[@]}"; do
        [[ -n "${dtb}" ]] || continue
        local dtb_path="${out}/dtbs/${dtb}"
        if [[ -f "${dtb_path}" ]]; then
            # Check magic bytes: FDT begins with 0xD00DFEED (big-endian)
            local magic
            magic="$(xxd -p -l 4 "${dtb_path}" 2>/dev/null || od -A n -t x1 -N 4 "${dtb_path}" | tr -d ' \n')"
            magic="${magic,,}"  # lowercase
            if [[ "${magic}" == "d00dfeed" ]]; then
                workshop_log "  [PASS] DTB magic valid: ${dtb}"
            else
                # Try dtc as a fallback validator
                if dtc -I dtb -O dts "${dtb_path}" > /dev/null 2>&1; then
                    workshop_log "  [PASS] DTB valid (dtc): ${dtb}"
                else
                    errors+=("CHECK 5 FAILED: ${dtb} is not a valid FDT blob (magic=${magic})")
                fi
            fi
        fi
    done

    # 6. Module tree exists at expected kernel release
    if [[ ! -d "${out}/modules/${kernelrelease}" ]]; then
        errors+=("CHECK 6 FAILED: out/kernel/modules/${kernelrelease}/ not found.\n" \
            "  The build may have used a different KERNELRELEASE.")
    else
        workshop_log "  [PASS] Module tree exists: ${kernelrelease}"
    fi

    # 7. modules.dep exists (populated by depmod in modules_install)
    if [[ ! -f "${out}/modules/${kernelrelease}/modules.dep" ]]; then
        errors+=("CHECK 7 FAILED: modules.dep not found in out/kernel/modules/${kernelrelease}/")
    else
        workshop_log "  [PASS] modules.dep present"
    fi

    # 8. System.map exists
    if [[ ! -s "${out}/metadata/System.map" ]]; then
        errors+=("CHECK 8 FAILED: out/kernel/metadata/System.map missing or empty")
    else
        workshop_log "  [PASS] System.map present ($(wc -l < "${out}/metadata/System.map") symbols)"
    fi

    # 9. .config exists
    if [[ ! -s "${out}/metadata/config" ]]; then
        errors+=("CHECK 9 FAILED: out/kernel/metadata/config missing or empty")
    else
        workshop_log "  [PASS] .config present"
    fi

    # 10. Kernel release in metadata matches expected
    if [[ -f "${out}/metadata/kernel-version" ]]; then
        local recorded_kr
        recorded_kr="$(cat "${out}/metadata/kernel-version")"
        if [[ "${recorded_kr}" == "${kernelrelease}" ]]; then
            workshop_log "  [PASS] kernel-version matches: ${kernelrelease}"
        else
            errors+=("CHECK 10 FAILED: kernel-version mismatch: got '${recorded_kr}', expected '${kernelrelease}'")
        fi
    else
        errors+=("CHECK 10 FAILED: out/kernel/metadata/kernel-version missing")
    fi

    # SHA verification (bonus check if expected_sha is provided)
    if [[ -n "${expected_sha}" ]] && [[ -f "${out}/metadata/build-info.yaml" ]]; then
        local recorded_sha
        recorded_sha="$(grep 'resolved_sha:' "${out}/metadata/build-info.yaml" | awk '{print $2}')"
        if [[ "${recorded_sha}" == "${expected_sha}" ]]; then
            workshop_log "  [PASS] Commit SHA verified: ${expected_sha}"
        else
            errors+=("SHA CHECK FAILED: build-info records ${recorded_sha}, expected ${expected_sha}")
        fi
    fi

    # Report
    if [[ ${#errors[@]} -gt 0 ]]; then
        workshop_log "Validation FAILED — ${#errors[@]} error(s):"
        for err in "${errors[@]}"; do
            workshop_log "  ${err}"
        done
        workshop_fail "Kernel build output validation failed. See errors above."
    fi

    workshop_log "=== All validation checks passed ==="
    workshop_log "Output: ${out}/"
    workshop_log "  image/Image.gz"
    workshop_log "  dtbs/"
    workshop_log "  modules/${kernelrelease}/"
    workshop_log "  metadata/"
}
