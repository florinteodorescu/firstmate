#!/usr/bin/env bash
# Behavior test: fm-spawn.sh must confirm a Claude positional launch brief was
# actually submitted.
#
# Claude takes the launch brief as a positional argument on the launch command, and
# a brief of more than one line is not always submitted by that argument alone:
# Claude leaves it in the composer waiting for its own Enter. Nothing noticed, so
# the worker started, never read a single instruction, and idled until a human
# looked at the pane. Kimi and Rovo already confirm their composer emptied; this
# covers Claude.
#
# The decision is unit-tested directly rather than through a live pane, because
# sourcing fm-spawn.sh would run it. The function is extracted from the real source
# so this test cannot drift from it, and driven with fake state and Enter steps.
# Counters live in files because the function reads state through a command
# substitution, so an in-memory counter would reset in a subshell.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SPAWN="$ROOT/bin/fm-spawn.sh"
TMP_ROOT=$(fm_test_tmproot fm-claude-brief-submit)

# Pull the real function out of fm-spawn.sh so this test cannot drift from it.
FUNC=$(awk '
  /^claude_confirm_brief_submitted\(\) \{/ { inside=1 }
  inside { print }
  inside && /^\}$/ { exit }
' "$SPAWN")

if [ -z "$FUNC" ]; then
  fail "fm-spawn.sh no longer defines claude_confirm_brief_submitted; a Claude launch brief can go unsubmitted again"
fi

mkdir -p "$TMP_ROOT"
COUNTER="$TMP_ROOT/counter"
ENTERS_FILE="$TMP_ROOT/enters"

# Scripted composer: each state read advances the cursor, holding the last scripted
# answer once the script runs out. The production call site passes no arguments, so
# the script itself lives in globals.
fake_state() {
  local cursor index i=0 answer
  cursor=$(cat "$COUNTER" 2>/dev/null || echo 0)
  index=$cursor
  [ "$index" -lt "$ANSWER_COUNT" ] || index=$((ANSWER_COUNT - 1))
  echo $((cursor + 1)) >"$COUNTER"
  for answer in $SCRIPTED; do
    [ "$i" -eq "$index" ] && { printf '%s' "$answer"; return 0; }
    i=$((i + 1))
  done
  printf 'empty'
}
fake_enter() {
  local n
  n=$(cat "$ENTERS_FILE" 2>/dev/null || echo 0)
  echo $((n + 1)) >"$ENTERS_FILE"
}

enters_count() { cat "$ENTERS_FILE" 2>/dev/null || echo 0; }

# Run the real function against a scripted composer. Results land in RESULT rather
# than stdout capture, because the function runs in this shell, not a subshell.
run_confirm() { # <retries> <answers...>
  local retries=$1
  shift
  SCRIPTED="$*"
  ANSWER_COUNT=$#
  echo 0 >"$COUNTER"
  echo 0 >"$ENTERS_FILE"
  RESULT=$(
    # The extracted source and the invocation must be newline-separated, or the
    # closing brace runs into the call.
    eval "$(printf '%s\n%s' "$FUNC" "claude_confirm_brief_submitted $retries 0 fake_state fake_enter")"
  )
}

test_submits_a_brief_that_starts_pending() {
  run_confirm 3 pending empty
  [ "$RESULT" = empty ] || fail "a brief pending then empty should report empty, got '$RESULT'"
  [ "$(enters_count)" -eq 1 ] || fail "a pending composer must be pressed exactly once, got $(enters_count)"
  pass "claude brief submission: presses Enter while the brief is pending, then reports empty"
}

test_submits_a_multi_line_brief_that_needs_two_enters() {
  run_confirm 4 pending pending empty
  [ "$RESULT" = empty ] || fail "two pending reads then empty should report empty, got '$RESULT'"
  [ "$(enters_count)" -eq 2 ] || fail "two pending reads must press Enter twice, got $(enters_count)"
  pass "claude brief submission: keeps pressing Enter until a multi-line brief is submitted"
}

test_refuses_a_brief_that_never_submits() {
  run_confirm 3 pending pending pending
  [ "$RESULT" = pending ] || fail "a brief that never submits must report pending, got '$RESULT'"
  [ "$(enters_count)" -eq 3 ] || fail "retries must bound the Enter attempts, got $(enters_count)"
  pass "claude brief submission: a brief that never submits reports pending so the launch can refuse"
}

test_tolerates_an_unclassifiable_pane() {
  run_confirm 3 unknown
  [ "$RESULT" = unknown ] || fail "an unclassifiable pane must pass through as unknown, got '$RESULT'"
  [ "$(enters_count)" -eq 0 ] || fail "an unknown pane must not be pressed, got $(enters_count)"
  pass "claude brief submission: an unclassifiable pane is tolerated, not failed"
}

test_launch_path_confirms_a_claude_brief() {
  grep -q 'claude_confirm_brief_submitted' "$SPAWN" ||
    fail "fm-spawn.sh no longer calls claude_confirm_brief_submitted after the launch Enter"
  grep -q 'if \[ "\$HARNESS" = claude \]; then' "$SPAWN" ||
    fail "the claude brief-submission gate is missing or no longer scoped to claude"
  pass "fm-spawn: the claude launch path confirms the brief was submitted"
}

test_submits_a_brief_that_starts_pending
test_submits_a_multi_line_brief_that_needs_two_enters
test_refuses_a_brief_that_never_submits
test_tolerates_an_unclassifiable_pane
test_launch_path_confirms_a_claude_brief
