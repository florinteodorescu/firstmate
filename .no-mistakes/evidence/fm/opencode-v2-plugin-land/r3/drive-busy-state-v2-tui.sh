#!/usr/bin/env bash
# Live driver: generate the busy-state plugin with the real fm-spawn (fake pane,
# isolated home), then run the real OpenCode v2.0.18 TUI (--auto --standalone)
# in a private tmux socket, submit the prompt, wait for the turn to end, and
# read the busy record + turn-ended marker. Worker TUIs stay alive after a turn.
set -u
cd "$WT_ROOT"
. tests/fixtures.sh
. "$ROOT/bin/fm-busy-lib.sh"
OC2=/home/escu/.local/share/mise/installs/node/26.8.2/lib/node_modules/@opencode/cli/bin/opencode.exe
TMP_ROOT=$(fm_test_tmproot fm-live-busy-tui)
id=busy-tui-1; case_dir=$TMP_ROOT/c; home=$case_dir/home; proj=$case_dir/project; wt=$case_dir/wt
fakebin=$(make_spawn_fakebin "$case_dir/fake" pi opencode claude codex gemini)
fm_test_spawn_home "$home" opencode
fm_git_worktree "$proj" "$wt" "wt-live"
fm_test_spawn_brief "$home" "$id"
GROK_HOME="$home/grok-home" fm_test_run_spawn "$home" "$wt" "$fakebin" "$id" "$proj" --mode no-mistakes --yolo off >/dev/null
echo "== busy classify after spawn: $(fm_busy_classify tmux fake:w opencode "$id" "$home/state")"
rm -f "$home/state/$id.turn-ended"
export TMUX_TMPDIR="$case_dir/tmux"; mkdir -p "$TMUX_TMPDIR"
T="tmux -L fm-lab-busy"
$T new-session -d -s w -x 200 -y 50 -c "$wt" "$OC2" --auto --standalone --prompt "Reply with exactly the word OK and nothing else."
sleep 12
$T send-keys -t w Enter
for i in $(seq 1 60); do
  sleep 2
  [ -e "$home/state/$id.turn-ended" ] && break
done
sleep 3
echo "== turn-ended marker: $([ -e "$home/state/$id.turn-ended" ] && echo PRESENT || echo MISSING) (after ~$((i*2))s)"
echo "== busy record: $(cat "$home/state/$id.busy-state")"
echo "== busy classify after turn (TUI still running): $(fm_busy_classify tmux fake:w opencode "$id" "$home/state")"
echo "== TUI pane:"; $T capture-pane -p -t w | sed '/^\s*$/d' | tail -20
# second turn: busy should flip back to busy, then idle again
rm -f "$home/state/$id.turn-ended"
$T send-keys -t w "Reply with exactly the word AGAIN and nothing else." ; sleep 1; $T send-keys -t w Enter
sleep 1; echo "== mid second turn record: $(cat "$home/state/$id.busy-state")"
for i in $(seq 1 60); do sleep 2; [ -e "$home/state/$id.turn-ended" ] && break; done
sleep 3
echo "== second turn-ended marker: $([ -e "$home/state/$id.turn-ended" ] && echo PRESENT || echo MISSING)"
echo "== busy record after second turn: $(cat "$home/state/$id.busy-state")"
echo "== busy classify: $(fm_busy_classify tmux fake:w opencode "$id" "$home/state")"
$T capture-pane -p -t w | sed '/^\s*$/d' | tail -12
$T kill-server
