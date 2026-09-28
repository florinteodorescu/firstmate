#!/usr/bin/env bash
# Live driver: generate the OpenCode busy-state plugin with the REAL fm-spawn
# (fake tmux pane, isolated home), then run the REAL OpenCode v2.0.18 CLI in the
# generated worktree and check the busy record + turn-ended marker it writes.
set -u
cd "$WT_ROOT"
. tests/fixtures.sh
. "$ROOT/bin/fm-busy-lib.sh"
OC2=/home/escu/.local/share/mise/installs/node/26.8.2/lib/node_modules/@opencode/cli/bin/opencode.exe
TMP_ROOT=$(fm_test_tmproot fm-live-busy)
id=busy-live-1; case_dir=$TMP_ROOT/c; home=$case_dir/home; proj=$case_dir/project; wt=$case_dir/wt
fakebin=$(make_spawn_fakebin "$case_dir/fake" pi opencode claude codex gemini)
fm_test_spawn_home "$home" opencode
fm_git_worktree "$proj" "$wt" "wt-live"
fm_test_spawn_brief "$home" "$id"
GROK_HOME="$home/grok-home" fm_test_run_spawn "$home" "$wt" "$fakebin" "$id" "$proj" --mode no-mistakes --yolo off >/dev/null
cat > "$wt/.opencode/plugins/zz-probe.js" <<PEOF
import { appendFileSync } from "node:fs";
export default { id: "zz-probe", async setup(ctx) { const c = new AbortController(); void (async () => { for await (const e of ctx.event.subscribe({ signal: c.signal })) { if (/^session\.(execution|idle|status|created)/.test(e.type)) appendFileSync("$case_dir/probe.jsonl", JSON.stringify({t: e.type, d: e.data}).slice(0,200) + "\n"); } })().catch(() => {}); return () => c.abort(); } };
PEOF
echo "== generated plugin: $wt/.opencode/plugins/fm-busy-state.js"
ls -la "$wt/.opencode/plugins/"
echo "== busy classify after spawn: $(fm_busy_classify tmux fake:w opencode "$id" "$home/state")"
rm -f "$home/state/$id.turn-ended"
echo "== running real opencode $("$OC2" --version) run --auto in the worktree"
( cd "$wt" && timeout 240 "$OC2" run --auto --standalone --print-logs "Reply with exactly the word OK and nothing else." < /dev/null ) > "$case_dir/oc.out" 2> "$case_dir/oc.err"
echo "opencode exit=$?"
echo "== stdout:"; cat "$case_dir/oc.out"
echo "== plugin load lines:"; grep -iE 'plugin' "$case_dir/oc.err" | grep -iE 'fm-busy|fail|error|must' | cut -c1-400 | head -20
echo "== session status/idle/execution events seen:"; grep -oE 'event.type=session\.(status|idle|execution[a-z.]*)' "$case_dir/oc.err" | sort | uniq -c
echo "== busy classify after turn: $(fm_busy_classify tmux fake:w opencode "$id" "$home/state")"
if [ -e "$home/state/$id.turn-ended" ]; then echo "== turn-ended marker: PRESENT"; else echo "== turn-ended marker: MISSING"; fi
ls -la "$home/state" | grep "$id"
echo "== all event types published during the turn:"; grep -oE 'event.type=[a-z._]+' "$case_dir/oc.err" | sort | uniq -c
cp "$case_dir/oc.err" "$EVID/busy-state-v2-opencode-server.log"
echo "== busy record:"; cat "$home/state/$id.busy-state"; echo; echo "== probe (session lifecycle events seen by a sibling plugin):"; cat "$case_dir/probe.jsonl"
