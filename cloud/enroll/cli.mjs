#!/usr/bin/env node
// Beheer vanaf de VPS:  docker compose exec enroll node cli.mjs <cmd>
//   new-code [label]        eenmalige enrollment-code (10 min)
//   list                    servers, installateurs, open codes
//   revoke <serverId>       server intrekken (wg-peer en subdomein weg)
//   installer <naam>        wg-config voor een installateur (ETS)
//   sync                    peers en Caddyfile opnieuw toepassen
const base = process.env.ENROLL_BASE || `http://127.0.0.1:${process.env.PORT || 8090}`;
const token = process.env.ENROLL_ADMIN_TOKEN || "";

async function call(method, path, body) {
  const res = await fetch(base + path, {
    method,
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json"
    },
    body: body ? JSON.stringify(body) : undefined
  });
  const text = await res.text();
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    data = { raw: text };
  }
  if (!res.ok) {
    console.error(`fout ${res.status}:`, data.error || text);
    process.exit(1);
  }
  return data;
}

const [cmd, ...args] = process.argv.slice(2);

switch (cmd) {
  case "new-code": {
    const out = await call("POST", "/admin/codes", { label: args.join(" ") });
    console.log(`\nEnrollment-code: ${out.code}   (geldig ${out.expiresInMinutes} min, eenmalig)\n`);
    console.log("Op de NUC: ./installeer.sh  ->  Remote toegang via Archie Cloud? J  ->  code invoeren.\n");
    break;
  }
  case "list": {
    const out = await call("GET", "/admin/servers");
    console.log("\nServers:");
    for (const s of out.servers) {
      console.log(`  ${s.revoked ? "x" : " "} ${s.id}  ${s.wgAddress.padEnd(14)} ${s.remoteUrl}  ${s.label}`);
    }
    console.log("\nInstallateurs:");
    for (const i of out.installers) {
      console.log(`  ${i.revoked ? "x" : " "} ${i.name.padEnd(16)} ${i.wgAddress}`);
    }
    if (out.codes.length) {
      console.log("\nOpen codes:");
      for (const c of out.codes) console.log(`    ${c.code}  ${c.label}  (tot ${c.expiresAt})`);
    }
    console.log("");
    break;
  }
  case "revoke": {
    if (!args[0]) {
      console.error("gebruik: revoke <serverId>");
      process.exit(1);
    }
    await call("DELETE", `/admin/servers/${args[0]}`);
    console.log("ingetrokken");
    break;
  }
  case "installer": {
    const out = await call("POST", "/admin/installers", { name: args[0] });
    console.log(`\n# WireGuard-config voor ${out.name} (${out.wgAddress}); importeer in de WireGuard-app\n`);
    console.log(out.config);
    break;
  }
  case "sync": {
    const out = await call("POST", "/admin/sync");
    console.log(out);
    break;
  }
  default:
    console.log("gebruik: new-code [label] | list | revoke <id> | installer <naam> | sync");
    process.exit(cmd ? 1 : 0);
}
