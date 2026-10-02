#!/usr/bin/env bash
# Behavior test: `fm-captain-hold.sh open` must answer on a non-markdown backlog.
#
# A captain hold is a markdown-backend feature. On any other backend this home
# records no captain calls at all, so a task is provably NOT held. `open` used to
# exit 2 ("cannot tell") there, which wedged every caller that gates on its answer:
# teardown, local merge, PR merge, and the bearings board all refused, so on such a
# home nothing could ever be cleaned up or merged.
#
# The markdown home's existing answers must not change: an absent task is still 1
# (or 3 with --distinguish-absent), a held task is still 0, and an unreadable
# record that may hide a hold is still 2.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HOLD="$ROOT/bin/fm-captain-hold.sh"
TMP_ROOT=$(fm_test_tmproot fm-captain-hold-backend)

# A home whose backlog is not markdown-backed: captain holds cannot exist there.
# The backend is declared in the data root's .tasks.toml, which is where the
# resolver reads it from.
make_beads_home() {
  local home=$1 graph="$TMP_ROOT/beads-graph"
  mkdir -p "$home/config" "$home/data" "$home/state" "$graph"
  cat >"$home/.tasks.toml" <<EOF
backend = "beads"
[beads]
binary = "bd"
path = "$graph"
prefix = "test"
EOF
}

hold_status() { # <home> <args...>
  local home=$1
  shift
  FM_HOME="$home" \
    FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$home/state" \
    FM_DATA_OVERRIDE="$home/data" \
    FM_CONFIG_OVERRIDE="$home/config" \
    "$HOLD" open "$@" >/dev/null 2>&1
  printf '%s' $?
}

test_non_markdown_backend_is_provably_not_held() {
  local home="$TMP_ROOT/beads"
  make_beads_home "$home"
  local status
  status=$(hold_status "$home" some-task)
  # 1 = present and not held, which is what every gate needs in order to proceed.
  [ "$status" = 1 ] || fail "a backend that cannot express a captain hold must answer 'not held' (1), got $status"
  pass "captain-hold open: a non-markdown backend answers 'not held' instead of 'cannot tell'"
}

test_non_markdown_backend_still_answers_for_distinguish_absent() {
  local home="$TMP_ROOT/beads"
  make_beads_home "$home"
  local status
  status=$(hold_status "$home" some-task --distinguish-absent)
  # It must still answer rather than exit 2: a caller that distinguishes absence
  # needs "not held", and "cannot tell" is what wedged it.
  [ "$status" = 1 ] || fail "a non-markdown backend must still answer under --distinguish-absent, got $status"
  pass "captain-hold open: a non-markdown backend answers under --distinguish-absent too"
}

test_markdown_home_answers_are_unchanged() {
  local home="$TMP_ROOT/markdown"
  mkdir -p "$home/config" "$home/data" "$home/state"
  printf 'backend = "markdown"\n' >"$home/.tasks.toml"
  # No backlog file at all: this home records no calls, so an absent task is 1.
  local status
  status=$(hold_status "$home" absent-task)
  [ "$status" = 1 ] || fail "a markdown home with no backlog file must still answer 1, got $status"
  status=$(hold_status "$home" absent-task --distinguish-absent)
  [ "$status" = 3 ] || fail "a markdown home with no backlog file must still answer 3 for absent, got $status"
  pass "captain-hold open: markdown-home answers are unchanged (1 absent, 3 absent+distinguish)"
}

test_non_markdown_backend_is_never_zero() {
  # Zero means "held", i.e. cleanup and merges must stand aside. A backend that
  # cannot hold must never claim a hold exists.
  local home="$TMP_ROOT/beads"
  make_beads_home "$home"
  local status
  status=$(hold_status "$home" any-task)
  [ "$status" != 0 ] || fail "a non-markdown backend must never report a captain hold"
  pass "captain-hold open: a non-markdown backend never claims a hold exists"
}

test_non_markdown_backend_is_never_zero
test_non_markdown_backend_is_provably_not_held
test_non_markdown_backend_still_answers_for_distinguish_absent
test_markdown_home_answers_are_unchanged