#!/usr/bin/env bash
# Per-repo wired files and their lock/resolved counterparts.
# Each entry: REPO_DIR:FILE_PATH (relative to repo root)

WIRED=(
    "zcash_voting:Cargo.toml"
    "voting-circuits:voting-circuits/Cargo.toml"
    "vote-sdk:circuits/Cargo.toml"
    "zcash-swift-wallet-sdk:Cargo.toml"
    "zodl-ios:modules/Package.swift"
)

WIRED_LOCKS=(
    "zcash_voting:Cargo.lock"
    "voting-circuits:voting-circuits/Cargo.lock"
    "zcash-swift-wallet-sdk:Cargo.lock"
    "zodl-ios:modules/Package.resolved"
    "zodl-ios:secant.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
)
