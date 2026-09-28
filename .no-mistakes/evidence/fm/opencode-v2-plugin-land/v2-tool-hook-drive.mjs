// Drives the v2 default exports of the cd/pretool guards through ctx.tool.hook
// with the v2.0.18 execute.before event shape ({tool:"shell", input:{command}}).
import { pathToFileURL } from "node:url";
import { mkdtempSync, mkdirSync, writeFileSync, chmodSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync } from "node:child_process";
const root = mkdtempSync(join(tmpdir(), "fm-v2tool-"));
execFileSync("git", ["init", "-q", root]);
mkdirSync(join(root, "bin"));
for (const s of ["fm-cd-pretool-check.sh", "fm-arm-pretool-check.sh"]) {
  writeFileSync(join(root, "bin", s), '#!/bin/sh\ncase "$2" in *BLOCKME*) echo "blocked by stub owner" >&2; exit 2;; esac\nexit 0\n');
  chmodSync(join(root, "bin", s), 0o755);
}
for (const f of ["fm-primary-cd-check.js", "fm-primary-pretool-check.js"]) {
  const mod = await import(pathToFileURL(join(process.env.WT, ".opencode/plugins", f)).href);
  let hook;
  await mod.default.setup({ location: { directory: root }, tool: { hook: async (name, cb) => { if (name === "execute.before") hook = cb; } } });
  for (const ev of [
    { tool: "shell", input: { command: "echo BLOCKME" } },
    { tool: "shell", input: { command: "echo fine" } },
    { tool: "read", input: { command: "BLOCKME" } },
  ]) {
    let outcome = "allowed";
    try { await hook(ev); } catch (e) { outcome = "BLOCKED: " + e.message; }
    console.log(`${f} ${JSON.stringify(ev)} -> ${outcome}`);
  }
}
