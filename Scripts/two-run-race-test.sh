#!/usr/bin/env bash
# Real-CLI regression coverage for concurrent invocation of the compiled
# swift-mutation-testing binary, and a full-CLI-level proof of the escaped-child scope fix
# (8jq.2). Runs two real mutation-testing invocations concurrently over the same SPM fixture
# with planted mutant verdicts (general concurrent-invocation coverage -- this does NOT
# specifically discriminate 8jq.1's sandbox-sweep race: that race's window is the gap between
# mkdir and the owner-pid write, a handful of syscalls, only reachable via the
# sandboxRootCreatedHook test-only hook in SandboxCreationSweepRaceTests, which is 8jq.1's
# actual discriminating proof and runs as part of the standard `swift test` gate). Then runs a
# single real invocation whose mutant set includes one that times out immediately followed by
# a real, finite-duration mutant that's still in flight when the timeout's escaped-child
# cleanup sweep fires 5 seconds later, asserting the timeout doesn't poison that mutant's (or
# any other mutant's) verdict -- proving 8jq.2 holds at the full-CLI level, not just the
# hooked unit test.
#
# Exit 0: every planted verdict matched. Exit non-zero: prints the mismatch and fails. Phase 1
# is retried once before it fails -- see run_concurrent_race for why, and for what it still
# reports on the first attempt either way.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR="$ROOT_DIR/Fixtures/CalcLibrary"
SCRATCH_DIR="$(mktemp -d)"

trap 'rm -rf "$SCRATCH_DIR"' EXIT

log() { printf '%s\n' "$*" >&2; }
fail() { log "FAIL: $*"; exit 1; }

build_tool() {
    log "Building swift-mutation-testing..."
    swift build --package-path "$ROOT_DIR" >&2
    BIN="$(swift build --package-path "$ROOT_DIR" --show-bin-path)/swift-mutation-testing"
    [ -x "$BIN" ] || fail "built binary not found at $BIN"
}

# Reads the status of the single mutant identified by file/originalText/replacement.
mutant_status() {
    local report="$1" file="$2" original="$3" replacement="$4"
    jq -r --arg f "$file" --arg o "$original" --arg r "$replacement" '
        .files[$f].mutants
        | map(select(.originalText == $o and .replacement == $r))
        | if length == 1 then .[0].status else "MISSING(\(length))" end
    ' "$report"
}

assert_mutant_status() {
    local report="$1" label="$2" file="$3" original="$4" replacement="$5" expected="$6"
    local actual
    actual="$(mutant_status "$report" "$file" "$original" "$replacement")"
    if [ "$actual" != "$expected" ]; then
        fail "$label: $file ($original -> $replacement) expected status '$expected', got '$actual' (report: $report)"
    fi
}

status_count() {
    local report="$1" status="$2"
    jq --arg s "$status" '[.files[].mutants[] | select(.status == $s)] | length' "$report"
}

assert_status_count() {
    local report="$1" label="$2" status="$3" expected="$4"
    local actual
    actual="$(status_count "$report" "$status")"
    if [ "$actual" != "$expected" ]; then
        fail "$label: expected $expected mutants with status '$status', got $actual (report: $report)"
    fi
}

# The planted verdicts common to every run below (RaceTarget.swift, Calculator.swift,
# Validator.swift under RelationalOperatorReplacement) -- deterministic given the fixture's
# test coverage, independent of the timeout mutant in TimeoutTarget.swift.
assert_baseline_verdicts() {
    local report="$1" label="$2"

    assert_mutant_status "$report" "$label" \
        "/Sources/CalcLibrary/Calculator.swift" ">" ">=" "Survived"
    assert_mutant_status "$report" "$label" \
        "/Sources/CalcLibrary/Calculator.swift" ">" "<" "Killed"

    assert_mutant_status "$report" "$label" \
        "/Sources/CalcLibrary/RaceTarget.swift" ">" ">=" "Survived"
    assert_mutant_status "$report" "$label" \
        "/Sources/CalcLibrary/RaceTarget.swift" ">" "<" "Killed"
    assert_mutant_status "$report" "$label" \
        "/Sources/CalcLibrary/RaceTarget.swift" "==" "!=" "Killed"
    assert_mutant_status "$report" "$label" \
        "/Sources/CalcLibrary/RaceTarget.swift" "<" "<=" "Killed"
    assert_mutant_status "$report" "$label" \
        "/Sources/CalcLibrary/RaceTarget.swift" "<" ">" "Killed"

    assert_mutant_status "$report" "$label" \
        "/Sources/CalcLibrary/Validator.swift" ">=" ">" "Killed"
    assert_mutant_status "$report" "$label" \
        "/Sources/CalcLibrary/Validator.swift" ">=" "<=" "Killed"
    assert_mutant_status "$report" "$label" \
        "/Sources/CalcLibrary/Validator.swift" "<=" "<" "Survived"
    assert_mutant_status "$report" "$label" \
        "/Sources/CalcLibrary/Validator.swift" "<=" ">=" "Killed"

    assert_status_count "$report" "$label" "Killed" 8
    assert_status_count "$report" "$label" "Unviable" 0
}

# The planted verdicts for UnaffectedSlowMutant.swift's mutants -- a mutant that takes a real,
# finite 8-second delay before returning the same value as the original (a genuine Survived,
# not a timeout). Scheduled immediately after TimeoutTarget's timeout mutant under
# --concurrency 1 so it is still in flight when the escaped-child cleanup sweep for that
# timeout fires 5 seconds later -- exactly the collateral-kill window 8jq.2 fixed.
assert_slow_real_mutant_verdicts() {
    local report="$1" label="$2"

    assert_mutant_status "$report" "$label" \
        "/Sources/CalcLibrary/UnaffectedSlowMutant.swift" "<" "<=" "Survived"
    assert_mutant_status "$report" "$label" \
        "/Sources/CalcLibrary/UnaffectedSlowMutant.swift" "<" ">" "Survived"
}

# Phase 1: two real runs, started concurrently, over the same fixture project. General
# regression coverage for real concurrent CLI invocation -- both runs must report every
# planted verdict correctly with no interference between them. This does NOT specifically
# discriminate 8jq.1's sandbox-sweep race: that race's window (between sandbox-directory
# creation and the owner-pid write) is a handful of syscalls wide, not time-bounded, so plain
# concurrent invocation cannot reliably land a second process's startup sweep inside it.
# 8jq.1's actual discriminating proof is SandboxCreationSweepRaceTests, which holds the window
# open with sandboxRootCreatedHook and runs as part of the standard `swift test` gate.
#
# A failed attempt is retried once before the check fails. Each invocation already builds and
# tests in a sandbox root of its own (SandboxFactory.makeSandboxRoot names every one after a
# fresh UUID, and the build directory and derived data sit inside it) and Phase 1 runs with the
# result cache off, so the only state two concurrent invocations still share is the host's: the
# toolchain's global caches, and the machine's CPU, memory and disk. Interference from those is
# not what this check exists to report, and it has produced one-off verdicts that no rerun
# reproduced. A regression in concurrent invocation does reproduce, so requiring the same
# failure twice still fails the check on one -- and every failed attempt prints its diagnostics
# whether or not the retry goes on to pass.
run_concurrent_race() {
    log "=== Phase 1: two concurrent real runs over the same fixture ==="

    local attempt
    for attempt in 1 2; do
        if concurrent_race_attempt "$attempt"; then
            log "Phase 1 passed: both concurrent runs reported every planted verdict correctly."
            return 0
        fi

        if [ "$attempt" -eq 1 ]; then
            log "Phase 1 attempt 1 failed; retrying once before failing the check."
        fi
    done

    fail "Phase 1 failed on both attempts -- see each attempt's diagnostics above"
}

# One Phase 1 attempt, run in a subshell so that a mismatch ends the attempt rather than the
# script: `fail` is redefined inside it to report the mismatch and exit the subshell, leaving
# run_concurrent_race to decide whether this attempt's failure is the check's failure. Each
# attempt reports into files of its own so nothing a retry reads is left over from before it.
concurrent_race_attempt() {
    local attempt="$1"

    (
        local report1="$SCRATCH_DIR/concurrent-$attempt-1.json"
        local report2="$SCRATCH_DIR/concurrent-$attempt-2.json"
        local log1="$SCRATCH_DIR/concurrent-$attempt-1.log"
        local log2="$SCRATCH_DIR/concurrent-$attempt-2.log"

        fail() {
            log "Phase 1 attempt $attempt: $*"
            dump_run_diagnostics "concurrent run 1" "$report1" "$log1"
            dump_run_diagnostics "concurrent run 2" "$report2" "$log2"
            exit 1
        }

        "$BIN" "$FIXTURE_DIR" \
            --operator RelationalOperatorReplacement \
            --exclude "Sources/CalcLibrary/TimeoutTarget.swift" \
            --exclude "Sources/CalcLibrary/UnaffectedSlowMutant.swift" \
            --no-cache --quiet --output "$report1" \
            >"$log1" 2>&1 &
        local pid1=$!

        "$BIN" "$FIXTURE_DIR" \
            --operator RelationalOperatorReplacement \
            --exclude "Sources/CalcLibrary/TimeoutTarget.swift" \
            --exclude "Sources/CalcLibrary/UnaffectedSlowMutant.swift" \
            --no-cache --quiet --output "$report2" \
            >"$log2" 2>&1 &
        local pid2=$!

        local status1=0 status2=0
        wait "$pid1" || status1=$?
        wait "$pid2" || status2=$?

        [ "$status1" -eq 0 ] || fail "concurrent run 1 exited with status $status1"
        [ "$status2" -eq 0 ] || fail "concurrent run 2 exited with status $status2"

        assert_baseline_verdicts "$report1" "concurrent run 1"
        assert_status_count "$report1" "concurrent run 1" "Survived" 5

        assert_baseline_verdicts "$report2" "concurrent run 2"
        assert_status_count "$report2" "concurrent run 2" "Survived" 5
    )
}

# Everything a failed run leaves to diagnose it with: its output, and the verdict it recorded
# for every mutant. One mismatched verdict says nothing on its own about whether the schema
# build lost a single file's mutants or was lost entirely, and the whole verdict set does.
dump_run_diagnostics() {
    local label="$1" report="$2" log_file="$3"

    log "--- $label output ---"
    if [ -f "$log_file" ]; then
        cat "$log_file" >&2
    else
        log "  (no output captured)"
    fi

    log "--- $label verdicts ---"
    if [ -f "$report" ]; then
        jq -r '
            .files
            | to_entries[]
            | .key as $file
            | .value.mutants[]
            | "  \($file) (\(.originalText) -> \(.replacement)): \(.status)"
        ' "$report" >&2
    else
        log "  (no report written)"
    fi
}

# Phase 2: a single real run whose mutant set includes one mutant that parks the test process
# (a 60s sleep on the branch every tested input takes under the mutation) until the tool's own
# per-mutant timeout kills it, immediately followed -- under --concurrency 1, so it lands on
# the very next test run -- by a mutant with a real, finite 8-second delay that is still in
# flight 5 seconds later, when the escaped-child cleanup sweep for the timed-out mutant fires.
# Proves 8jq.2 (killDescendants must stay scoped to the timed-out mutant's own descendants) at
# the full CLI level: neither that mutant nor any other mutant's verdict may be poisoned by the
# timeout's cleanup.
run_timeout_shape() {
    log "=== Phase 2: one timeout mutant alongside real pass/fail verdicts ==="

    local report="$SCRATCH_DIR/timeout-shape.json"

    "$BIN" "$FIXTURE_DIR" \
        --operator RelationalOperatorReplacement \
        --concurrency 1 \
        --timeout 30 \
        --no-cache --quiet --output "$report"

    assert_baseline_verdicts "$report" "timeout-shape run"
    assert_mutant_status "$report" "timeout-shape run" \
        "/Sources/CalcLibrary/TimeoutTarget.swift" "<" "<=" "Survived"
    assert_mutant_status "$report" "timeout-shape run" \
        "/Sources/CalcLibrary/TimeoutTarget.swift" "<" ">" "Timeout"
    assert_slow_real_mutant_verdicts "$report" "timeout-shape run"

    assert_status_count "$report" "timeout-shape run" "Survived" 8
    assert_status_count "$report" "timeout-shape run" "Timeout" 1

    log "Phase 2 passed: the timeout mutant reported Timeout and every other mutant's verdict was unaffected."
}

main() {
    build_tool
    run_concurrent_race
    run_timeout_shape
    log "All two-run race assertions passed."
}

main "$@"
