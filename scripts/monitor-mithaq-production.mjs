const checks = [
  {
    name: "MITHAQ production website",
    url: "https://mithaq-esv.pages.dev/",
    validate: async (response, body) =>
      response.ok &&
      body.includes('id="entryGate"') &&
      body.includes('id="aiAssistant"') &&
      body.includes('id="mithaqAdminChatForm"') &&
      body.includes('window.reportMithaqClientError'),
  },
  {
    name: "MITHAQ service worker",
    url: "https://mithaq-esv.pages.dev/sw.js",
    validate: async (response, body) =>
      response.ok && body.includes("addEventListener('fetch'") && body.includes("mithaq-shell"),
  },
  {
    name: "MITHAQ AI worker health",
    url: "https://mithaq-ai-chat.w0000000000w00.workers.dev/health",
    validate: async (response, body) => {
      if (!response.ok) return false;
      try {
        const data = JSON.parse(body);
        return data.ok === true &&
          data.service === "mithaq-managed-ai" &&
          data.admin_capabilities?.runtime_error_reporting === true;
      } catch {
        return false;
      }
    },
  },
];

let failed = false;
for (const check of checks) {
  try {
    const response = await fetch(check.url, {
      cache: "no-store",
      signal: AbortSignal.timeout(15000),
      headers: { "user-agent": "MITHAQ-production-monitor/1.0" },
    });
    const body = await response.text();
    const passed = await check.validate(response, body);
    console.log(`${passed ? "PASS" : "FAIL"} ${check.name} — HTTP ${response.status}`);
    if (!passed) {
      failed = true;
      console.error(body.slice(0, 500));
    }
  } catch (error) {
    failed = true;
    console.error(`FAIL ${check.name} — ${error.message}`);
  }
}
if (failed) process.exit(1);
console.log("All MITHAQ production smoke checks passed.");
