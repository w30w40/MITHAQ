import { readFileSync, writeFileSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const html = readFileSync("index.html", "utf8");
const required = [
  'id="entryGate"',
  'id="entrySignup"',
  'id="aiAssistant"',
  'id="mithaqAdminChatForm"',
  'id="mithaqAiRunDiagnostics"',
  'navigator.serviceWorker.register',
  'window.reportMithaqClientError',
  'mithaq_admin_ai_client_errors'
];
const missing = required.filter((needle) => !html.includes(needle));
if (missing.length) {
  console.error("Missing required MITHAQ app markers:", missing.join(", "));
  process.exit(1);
}

const scripts = [];
const pattern = /<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi;
for (const match of html.matchAll(pattern)) {
  if (/\bsrc\s*=/.test(match[1])) continue;
  const source = match[2].trim();
  if (source) scripts.push(source);
}
if (!scripts.length) {
  console.error("No inline JavaScript blocks found.");
  process.exit(1);
}

let failed = false;
for (let i = 0; i < scripts.length; i++) {
  const file = join(tmpdir(), `mithaq-inline-${i}.js`);
  writeFileSync(file, scripts[i], "utf8");
  const result = spawnSync(process.execPath, ["--check", file], { encoding: "utf8" });
  unlinkSync(file);
  if (result.status !== 0) {
    failed = true;
    console.error(`Inline script ${i + 1} failed syntax check:`);
    console.error(result.stderr || result.stdout);
  }
}
const sw = readFileSync("sw.js", "utf8");
const swFile = join(tmpdir(), "mithaq-sw-check.js");
writeFileSync(swFile, sw, "utf8");
const swResult = spawnSync(process.execPath, ["--check", swFile], { encoding: "utf8" });
unlinkSync(swFile);
if (swResult.status !== 0) {
  failed = true;
  console.error("Service worker syntax check failed:");
  console.error(swResult.stderr || swResult.stdout);
}
const worker = readFileSync("cloudflare/mithaq-ai-chat/worker.js", "utf8");
const workerFile = join(tmpdir(), "mithaq-worker-check.mjs");
writeFileSync(workerFile, worker, "utf8");
const workerResult = spawnSync(process.execPath, ["--check", workerFile], { encoding: "utf8" });
unlinkSync(workerFile);
if (workerResult.status !== 0) {
  failed = true;
  console.error("MITHAQ AI Worker syntax check failed:");
  console.error(workerResult.stderr || workerResult.stdout);
}
if (!worker.includes('/client-error') || !worker.includes('mithaq_report_client_error')) {
  failed = true;
  console.error("MITHAQ AI Worker is missing the client error reporting endpoint.");
}
if (failed) process.exit(1);
console.log(`MITHAQ static checks passed: required app markers, ${scripts.length} inline scripts, service worker, and AI Worker syntax.`);
