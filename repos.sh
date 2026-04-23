#!/usr/bin/env bash
# Workspace manifest. Single source of truth for:
#   - child-repo clone URLs (REPOS)
#   - named states — branch combinations that cycle as releases ship (STATES)
#   - per-state branches and wired files (BRANCHES_*, WIRED_*, WIRED_LOCKS_*)
#
# Active state lives in .wiring/current-state (defaults to STATES[0] if absent).
# Switch with: mise run wire:state <name>
# Apply local overrides with: mise run wire:local

# ─── Child repos ─────────────────────────────────────────
# Format: dir|clone_url. Branch comes from the active state's BRANCHES_* array.
REPOS=(
    "zcash_voting|git@github.com:valargroup/zcash_voting.git"
    "librustzcash|git@github.com:valargroup/librustzcash.git"
    "vote-nullifier-pir|https://github.com/valargroup/vote-nullifier-pir.git"
    "vote-sdk|https://github.com/valargroup/vote-sdk"
    "voting-circuits|https://github.com/valargroup/voting-circuits.git"
    "zcash-swift-wallet-sdk|git@github.com:valargroup/zcash-swift-wallet-sdk.git"
    "zodl-ios|git@github.com:valargroup/zodl-ios.git"
    "shielded-vote-book|https://github.com/valargroup/shielded-vote-book"
    "token-holder-voting-config|https://github.com/valargroup/token-holder-voting-config.git"
    "vote-infrastructure|https://github.com/valargroup/vote-infrastructure.git"
)

# ─── States ──────────────────────────────────────────────
# Ordered. First entry is the default when .wiring/current-state is missing.
# Labels are intentionally relative — when `next` ships, rename it to `current`
# and start a new `next` with fresh branches.
STATES=("current" "next")

# ─── current: deployed zodl (pre-orchard-0.12) ───────────
BRANCHES_current=(
    "zcash_voting:main"
    "librustzcash:shielded-voting-wallet-support"
    "vote-nullifier-pir:main"
    "vote-sdk:main"
    "voting-circuits:main"
    "zcash-swift-wallet-sdk:shielded-vote"
    "zodl-ios:shielded-vote"
    "shielded-vote-book:main"
    "token-holder-voting-config:main"
    "vote-infrastructure:main"
)
WIRED_current=(
    "zcash_voting:Cargo.toml"
    "voting-circuits:voting-circuits/Cargo.toml"
    "vote-sdk:circuits/Cargo.toml"
    "zcash-swift-wallet-sdk:Cargo.toml"
    "zodl-ios:modules/Package.swift"
    "zodl-ios:secant.xcodeproj/project.pbxproj"
    "zodl-ios:zashi-internal-Info.plist"
)
WIRED_LOCKS_current=(
    "zcash_voting:Cargo.lock"
    "voting-circuits:voting-circuits/Cargo.lock"
    "zcash-swift-wallet-sdk:Cargo.lock"
    "zodl-ios:modules/Package.resolved"
    "zodl-ios:secant.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
)

# ─── next: orchard-0.12 + zodl 3.4.0 release ─────────────
# zodl-ios on shielded-vote-3.4.0 declares zcash-swift-wallet-sdk as an
# XCLocalSwiftPackageReference directly in the pbxproj, so no Package.swift
# swap is needed for this state.
BRANCHES_next=(
    "zcash_voting:greg/orchard-0.12"
    "librustzcash:shielded-vote-for-zodl-3.4.0"
    "vote-nullifier-pir:main"
    "vote-sdk:greg/orchard-0.12"
    "voting-circuits:greg/orchard-0.12"
    "zcash-swift-wallet-sdk:shielded-vote-2.4.10"
    "zodl-ios:shielded-vote-3.4.0"
    "shielded-vote-book:main"
    "token-holder-voting-config:main"
    "vote-infrastructure:main"
)
WIRED_next=(
    "zcash_voting:Cargo.toml"
    "voting-circuits:voting-circuits/Cargo.toml"
    "vote-sdk:circuits/Cargo.toml"
    "zcash-swift-wallet-sdk:Cargo.toml"
)
WIRED_LOCKS_next=(
    "zcash_voting:Cargo.lock"
    "voting-circuits:voting-circuits/Cargo.lock"
    "zcash-swift-wallet-sdk:Cargo.lock"
)

# ─── Helpers ─────────────────────────────────────────────
# Tasks call `wiring_load_state <state>` to populate plain BRANCHES / WIRED /
# WIRED_LOCKS arrays from the state-specific ones. Bash 3.2 compatible.
wiring_state_key() {
    local s="$1"
    # Sanitize: replace anything that can't appear in a bash identifier.
    s="${s//[^a-zA-Z0-9]/_}"
    printf '%s' "$s"
}

wiring_load_state() {
    local state="$1"
    local key
    key="$(wiring_state_key "$state")"
    local base src
    for base in BRANCHES WIRED WIRED_LOCKS; do
        src="${base}_${key}"
        # Copy the state-specific array into a plain name, empty if unset.
        eval "${base}=(\"\${${src}[@]+\"\${${src}[@]}\"}\")"
    done
}

wiring_active_state() {
    # $1 = workspace root (defaults to $DIR if set)
    local root="${1:-${DIR:-.}}"
    if [ -f "$root/.wiring/current-state" ]; then
        cat "$root/.wiring/current-state"
    else
        printf '%s' "${STATES[0]}"
    fi
}

wiring_state_exists() {
    local name="$1"
    local s
    for s in "${STATES[@]}"; do
        [ "$s" = "$name" ] && return 0
    done
    return 1
}

wiring_branch_for_repo() {
    # $1 = repo dir, expects BRANCHES already loaded via wiring_load_state
    local repo="$1" entry
    for entry in "${BRANCHES[@]+"${BRANCHES[@]}"}"; do
        if [ "${entry%%:*}" = "$repo" ]; then
            printf '%s' "${entry#*:}"
            return 0
        fi
    done
    return 1
}
