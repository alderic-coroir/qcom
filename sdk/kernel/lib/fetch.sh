#!/usr/bin/bash
# sdk/kernel/lib/fetch.sh
# Qualcomm Silicon Workshop — Kernel SDK source management
#
# Implements the bare-clone + git worktree model described in
# QUALCOMM_WORKSHOP_DESIGN.md.
#
# Functions:
#   kernel_fetch_source ROOT   — ensure bare clone and Kernel SDK worktree
#                                are at the configured revision.

# Source guard
[[ -n "${_KERNEL_FETCH_SH:-}" ]] && return
_KERNEL_FETCH_SH=1

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

_kernel_fetch_bare_clone() {
    local root="${1}"
    local repo="${2}"
    local cache="${root}/cache/linux-qcom.git"

    if [[ -d "${cache}" ]]; then
        workshop_log "Updating bare clone at ${cache}..."
        # Redirect to stderr so this output does NOT pollute stdout/return values
        git -C "${cache}" fetch --tags --prune 2>&1 | \
            sed 's/^/[git-fetch] /' >&2 || \
            workshop_warn "git fetch encountered warnings (network issues?). Continuing with existing cache."
    else
        workshop_log "Creating bare clone of ${repo}..."
        workshop_log "This is a large repository (~1GB). This may take several minutes."
        mkdir -p "$(dirname "${cache}")"
        git clone --bare "${repo}" "${cache}" 2>&1 | \
            sed 's/^/[git-clone] /' >&2 || \
            workshop_fail "git clone failed. Check network connectivity and repository URL."
        workshop_log "Bare clone created at ${cache}"
    fi
}

_kernel_fetch_worktree() {
    local root="${1}"
    local ref_type="${2}"
    local ref_value="${3}"
    local wt="${root}/src/kernel/linux-qcom"
    local cache="${root}/cache/linux-qcom.git"

    # Resolve the full commit SHA for the requested ref
    local resolved_sha
    resolved_sha="$(git -C "${cache}" rev-parse "${ref_value}^{commit}" 2>/dev/null)" || \
        workshop_fail "Cannot resolve ref '${ref_value}' in cache. Try running kernel-clean --all and re-running."

    workshop_log "Resolved ${ref_value} → ${resolved_sha}"

    if [[ -d "${wt}" ]]; then
        # Worktree exists — verify it belongs to our bare clone
        local wt_git
        wt_git="$(git -C "${wt}" rev-parse --git-dir 2>/dev/null)" || \
            workshop_fail "Existing path ${wt} is not a git repo. Remove it manually and retry."

        # Check current HEAD
        local current_sha
        current_sha="$(git -C "${wt}" rev-parse HEAD 2>/dev/null || echo "unknown")"

        if [[ "${current_sha}" == "${resolved_sha}" ]]; then
            workshop_log "Worktree already at ${resolved_sha}. No update needed."
        else
            workshop_log "Moving worktree from ${current_sha} to ${resolved_sha}..."
            # Ensure clean checkout — fail if there are uncommitted changes
            if ! git -C "${wt}" diff --quiet HEAD 2>/dev/null; then
                workshop_fail "Worktree at ${wt} has uncommitted changes. Commit or stash before continuing."
            fi
            git -C "${wt}" checkout "${resolved_sha}" 2>&1 | sed 's/^/[git-checkout] /' >&2
        fi
    else
        workshop_log "Creating worktree at ${wt}..."
        mkdir -p "$(dirname "${wt}")"
        git -C "${cache}" worktree add "${wt}" "${resolved_sha}" 2>&1 | \
            sed 's/^/[git-worktree] /' >&2 || \
            workshop_fail "Failed to create git worktree."
    fi

    # Final verification: HEAD must match the resolved SHA
    local final_sha
    final_sha="$(git -C "${wt}" rev-parse HEAD)"
    if [[ "${final_sha}" != "${resolved_sha}" ]]; then
        workshop_fail "Worktree HEAD mismatch after checkout: got ${final_sha}, expected ${resolved_sha}"
    fi

    workshop_log "Worktree at ${wt} is at ${final_sha}"
    echo "${final_sha}"
}

# ---------------------------------------------------------------------------
# Public interface
# ---------------------------------------------------------------------------

# kernel_fetch_source ROOT REF_TYPE REF_VALUE KNOWN_GOOD_SHA
# Ensures the bare clone is up to date and the Kernel SDK worktree is
# checked out at the configured revision.
# Verifies the resolved commit matches KNOWN_GOOD_SHA when ref type is "tag"
# and KNOWN_GOOD_SHA is non-empty.
# Returns (prints) the resolved commit SHA.
kernel_fetch_source() {
    local root="${1}"
    local repo="${2}"
    local ref_type="${3}"
    local ref_value="${4}"
    local known_good_sha="${5:-}"

    workshop_log "=== Source acquisition ==="
    workshop_log "Repository: ${repo}"
    workshop_log "Ref: ${ref_type}:${ref_value}"

    _kernel_fetch_bare_clone "${root}" "${repo}"
    local resolved_sha
    resolved_sha="$(_kernel_fetch_worktree "${root}" "${ref_type}" "${ref_value}")"

    # Commit verification for the default known-good tag
    if [[ -n "${known_good_sha}" && "${ref_type}" == "tag" ]]; then
        if [[ "${resolved_sha}" != "${known_good_sha}" ]]; then
            workshop_fail \
                "Commit SHA mismatch for ref '${ref_value}'!\n" \
                "  Expected (known-good): ${known_good_sha}\n" \
                "  Got:                  ${resolved_sha}\n" \
                "The tag may have been recreated or the repository has diverged.\n" \
                "To override, set WORKSHOP_SKIP_SHA_CHECK=1 (not recommended)."
        fi
        workshop_log "Commit SHA verified: ${resolved_sha} matches known-good."
    fi

    echo "${resolved_sha}"
}
