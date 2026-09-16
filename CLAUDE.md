# Swift Mutation Testing

A Swift CLI for mutation testing of Xcode and SPM projects. It sandbox-mutates source code,
builds once via schematization, and runs the existing test suite against each mutant to
compute a mutation score — surfacing tests too weak to catch real bugs.

## Tech Stack
Swift 6.2 (Strict Concurrency, macOS 15+), SPM executable target. Only third-party dependency:
SwiftSyntax `from: 603.0.0`. Foundation + CryptoKit otherwise. This repo's own tests use Swift
Testing; the tool itself supports XCTest and Swift Testing as frameworks in *target* projects.
Docs: https://docs.swift.org/swift-book/

## What This Project Does
- CLI mutation testing for Xcode and SPM projects
- Sandbox-mutates source, builds once via schematization, runs the test suite per mutant
- 7 mutation operators; text/JSON (Stryker-compatible)/HTML/SonarQube reports
- Simulator pool management; SHA256-based result caching; CI-ready

## What This Project Does NOT Do
- No general static analysis/lint/duplication detection — owned by SwiftLint/swift-format/
  swift-cpd/swift-marshal, already configured
- No IDE/editor integration — CLI only
- No new third-party dependencies (see Dependencies)

## Technical Invariants
Hard invariants live in `CONTRIBUTING.md` (Technical Principles) — sandboxing,
build-for-testing exactly once, simulator-slot safety, stateless pipeline stages. Violating
any of them is rejected even if tests pass. Read that section before any structural change.

## Code Style
- Format: `swift-format format --in-place --parallel`. Lint: `swiftlint lint --strict --quiet`.
- Duplication: `swift-cpd`. Member ordering: `swift-marshal --path Sources`.
- Swift 6 Strict Concurrency is mandatory on every target — new code must be data-race safe,
  not merely compile.
- When conventions and simplicity conflict, simplicity wins.

## Testing
- Run before pushing: `swift test --no-parallel` (mirrors the PR gate).
- Full local run with coverage: `swift test --enable-code-coverage --no-parallel --quiet`.
- Use red/green TDD for every feature/bugfix — see `.claude/rules/tdd.md`.
- Mocking conventions, fixture requirements, and coverage target: see `CONTRIBUTING.md`
  (Testing section).

## Git Workflow
- Commits: Conventional Commits, single line only — no body, no `Co-Authored-By` trailer
  (the `no-coauthor-no-description` pre-commit hook rejects both).
- See `.claude/rules/git-workflow.md` for branch naming, worktrees, and this project's
  merge-commit PR policy.

## Issue Tracking
Use `bd` (beads), not TodoWrite — see `.claude/rules/issue-tracking.md`.

## Dependencies
- Zero external dependencies beyond `swift-syntax` — Apple system frameworks only otherwise.
- Always commit `Package.resolved`.

## Pre-commit & CI
- `pre-commit run --all-files` before committing.
- CI PR gate: `swift test --no-parallel`. `main` additionally runs coverage + SonarCloud
  (post-merge only, not a local gate).

## Reference Documents
**IMPORTANT:** Before starting any task, identify which docs below are relevant and read them
first. Load the full context before making changes.
- `CONTRIBUTING.md` (Technical Principles) — read before any structural change; violating
  these invariants is rejected even if tests pass.
- `CONTRIBUTING.md` (Testing section) — read when writing tests: mocking conventions,
  fixture requirements, coverage target.
- `Docs/Architecture/README.md` (+ `01`–`05`) — read when making structural changes: pipeline
  design, module map, schematization, execution model.
- `Docs/CodeBase/README.md` (+ `01`–`09`) — read when modifying a specific type, protocol, or
  pipeline stage; every one is documented here.
- `Docs/USAGE.MD` — read when touching CLI flags, the YAML config schema, output formats, or
  CI integration behavior.
- `Docs/MUTATION-RESULTS.md` — read when touching result classification (killed/survived/
  timeout/unviable).
- `Docs/STRYKER-COMPATIBILITY.md` — read when touching JSON report output; must stay
  Stryker-schema-compatible.

## Project Structure
Module map: see `Docs/Architecture/README.md` and `Docs/CodeBase/README.md`.
