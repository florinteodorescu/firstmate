// Drives the worktree's OpenCode v2 default exports with events shaped the way
// OpenCode v2.0.18 emits them (packages/schema/src/event.ts: {id,type,created,data})
// versus the v1 shape ({type, properties}) the unit tests use.
import { pathToFileURL } from "node:url";
import { mkdtempSync, mkdirSync, writeFileSync, chmodSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync } from "node:child_process";
const WT = process.env.WT;
// Fixture root whose bin/fm-sessionstart-nudge.sh prints a nudge.
const root = mkdtempSync(join(tmpdir(), "fm-v2repro-"));
execFileSync("git", ["init", "-q", root]);
mkdirSync(join(root, "bin"));
writeFileSync(join(root, "bin/fm-sessionstart-nudge.sh"), "#!/bin/sh\necho NUDGE-TEXT\n");
chmodSync(join(root, "bin/fm-sessionstart-nudge.sh"), 0o755);
async function drive(label, event) {
  const mod = await import(pathToFileURL(join(WT, ".opencode/plugins/fm-primary-sessionstart-nudge.js")).href + "?" + label);
  const prompts = [];
  const ctx = {
    location: { directory: root },
    session: { prompt: async (a) => prompts.push(a) },
    event: { subscribe: async function* () { yield event; } },
  };
  await mod.default.setup(ctx);
  for (let i = 0; i < 40 && prompts.length === 0; i++) await new Promise((r) => setTimeout(r, 50));
  console.log(`${label}: event=${JSON.stringify(event)} -> prompts=${JSON.stringify(prompts)}`);
  return prompts.length;
}
const v1 = await drive("v1-shape", { type: "session.created", properties: { sessionID: "ses_v1", info: { id: "ses_v1" } } });
const v2 = await drive("v2.0.18-shape", { id: "evt_1", created: 1, type: "session.created", data: { sessionID: "ses_v2", agent: "build" } });
console.log(`RESULT: v1-shaped nudges=${v1}, v2.0.18-shaped nudges=${v2}`);
process.exit(0);
