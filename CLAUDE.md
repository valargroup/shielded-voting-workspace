# shielded-voting-workspace

Multi-repo umbrella. Actual code lives in gitignored subdirectories — each is an independent git clone. See README.md for repo list, tasks, and setup.

## How to work here

- **Commits go to child repos**, not this umbrella. This repo only tracks coordination infra (mise tasks, wiring patches, manifests).
- **Check wiring state** before touching Cargo.toml or Package.swift — `mise run wire:status`. When wired local, these files have `skip-worktree` set and contain local path overrides that must not be committed.
- **To edit wired files**: edit directly while wired local, run `mise run wire:update` to regenerate the patch, then commit the patch file in this repo.
- **Never push while wired local** — `mise run git:push` enforces this, but be aware when pushing from child repos manually.
- **Rust compilation** happens from `zcash-swift-wallet-sdk/` — Cargo resolves all sibling repos through `[patch]` sections when wired local. Output: `zcash-swift-wallet-sdk/target/`.
- **iOS xcframework**: `zcash-swift-wallet-sdk/LocalPackages/` — auto-detected by Package.swift. Rebuild with `mise run start:ios` after Rust changes.

## FFI boundary (SDK ↔ Swift)

- Complex types: JSON serde across FFI (`serde_json` ↔ `Codable`)
- Simple types: `#[repr(C)]` structs
- Progress callbacks: `@convention(c)` with trampoline pattern
- Key files: `rust/src/voting.rs` (43 extern "C" functions), `VotingRustBackend.swift`, `VotingTypes.swift`

## Key paths

- SDK Rust FFI: `zcash-swift-wallet-sdk/rust/src/voting.rs`
- SDK Swift wrappers: `zcash-swift-wallet-sdk/Sources/ZcashLightClientKit/Rust/Voting/`
- iOS voting feature: `zodl-ios/modules/Sources/` (TCA modules)
- Wiring patches: `.wiring/*.patch`
- Repo manifest: `repos.sh`
- Mise tasks: `.mise/tasks/`

## Commit style

- Each commit represents one discrete, complete change — commit as you go, not one big squash at the end
- Clean history: no WIP commits, no "fix typo from last commit". If a fixup belongs to an earlier commit, amend or squash it in
- No co-authored-by, no Claude mention, no conventional commit prefixes
- Title: short, descriptive (<120 chars)
- Body: motivation and context (why, not what — the diff shows what changed)
