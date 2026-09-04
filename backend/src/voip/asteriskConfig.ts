import fs from "node:fs";
import path from "node:path";
import type { HouseConfig, IntercomDevice, VoipEndpoint } from "../types";
import { astSafe } from "./secrets";

export function asteriskConfDir(): string {
  return (
    process.env.ASTERISK_CONF_DIR?.trim() ||
    path.resolve(process.cwd(), "..", "docker", "data", "asterisk")
  );
}

function tlsPaths(): { cert: string; key: string } | null {
  const cert = process.env.TLS_CERT_PATH?.trim() || "/data/certs/tls.crt";
  const key = process.env.TLS_KEY_PATH?.trim() || "/data/certs/tls.key";
  if (fs.existsSync(cert) && fs.existsSync(key)) return { cert, key };
  return null;
}

function webrtcEndpoint(ep: VoipEndpoint): boolean {
  return ep.type === "panel" || ep.type === "app";
}

function pjsipEndpointBlock(opts: {
  ext: string;
  name: string;
  password: string;
  webrtc: boolean;
  context: string;
}): string {
  const ext = astSafe(opts.ext);
  const name = astSafe(opts.name);
  const password = astSafe(opts.password);
  const context = astSafe(opts.context);
  const media = opts.webrtc
    ? `webrtc=yes
dtls_auto_generate_cert=yes
media_encryption=dtls
ice_support=yes
rtcp_mux=yes
use_avpf=yes
`
    : `direct_media=no
rtp_symmetric=yes
force_rport=yes
rewrite_contact=yes
ice_support=no
`;
  return `; ${name}
[${ext}]
type=endpoint
context=${context}
disallow=all
allow=ulaw,alaw,opus,h264
${media}auth=${ext}
aors=${ext}
callerid="${name}" <${ext}>

[${ext}]
type=auth
auth_type=userpass
username=${ext}
password=${password}

[${ext}]
type=aor
max_contacts=1
remove_existing=yes
qualify_frequency=30
`;
}

export function groupDial(
  cfg: HouseConfig,
  groupId: string
): { dial: string; timeout: number } | null {
  const g = (cfg.voip?.groups ?? []).find((x) => x.id === groupId);
  if (!g) return null;
  const eps = cfg.voip?.endpoints ?? [];
  const byId = new Map(eps.map((e) => [e.id, e]));
  const targets = g.memberIds
    .map((id) => byId.get(id))
    .filter((e): e is VoipEndpoint => !!e?.ext)
    .map((e) => `PJSIP/${astSafe(e.ext)}`);
  if (targets.length === 0) return null;
  return { dial: targets.join("&"), timeout: g.timeoutSec ?? 30 };
}

export function doorContextName(ic: IntercomDevice): string {
  return `ring-${astSafe(ic.id).replace(/[^a-zA-Z0-9_-]/g, "")}`;
}

export function buildAsteriskFiles(cfg: HouseConfig): Record<string, string> {
  const v = cfg.voip ?? {};
  const sipPort = v.sipPort ?? 5060;
  const wsPort = v.wsPort ?? 8088;
  const wssPort = v.wssPort ?? 8089;
  const rtpStart = v.rtpStart ?? 10000;
  const rtpEnd = v.rtpEnd ?? 10100;
  const amiSecret = astSafe(v.amiSecret || "change-me");
  const tls = tlsPaths();

  const files: Record<string, string> = {};

  files["asterisk.conf"] = `[directories]
astetcdir => /etc/asterisk
astmoddir => /usr/lib/asterisk/modules
astvarlibdir => /var/lib/asterisk
astdbdir => /var/lib/asterisk
astkeydir => /var/lib/asterisk
astdatadir => /usr/share/asterisk
astagidir => /usr/share/asterisk/agi-bin
astspooldir => /var/spool/asterisk
astrundir => /var/run/asterisk
astlogdir => /var/log/asterisk

[options]
verbose = 3
`;

  files["modules.conf"] = `[modules]
autoload=yes
noload => chan_sip.so
noload => chan_skinny.so
noload => chan_oss.so
noload => chan_alsa.so
noload => app_voicemail.so
noload => cdr_csv.so
noload => cdr_sqlite3_custom.so
noload => pbx_ael.so
noload => pbx_dundi.so
noload => pbx_lua.so
`;

  files["logger.conf"] = `[general]
[logfiles]
console => notice,warning,error
messages => notice,warning,error
`;

  files["rtp.conf"] = `[general]
rtpstart=${rtpStart}
rtpend=${rtpEnd}
icesupport=true
stunaddr=stun.l.google.com:19302
`;

  files["http.conf"] = `[general]
enabled=yes
bindaddr=0.0.0.0
bindport=${wsPort}
${
    tls
      ? `tlsenable=yes
tlsbindaddr=0.0.0.0:${wssPort}
tlscertfile=${tls.cert}
tlsprivatekey=${tls.key}
`
      : "tlsenable=no\n"
  }`;

  files["manager.conf"] = `[general]
enabled=yes
webenabled=no
port=5038
bindaddr=127.0.0.1

[archie]
secret=${amiSecret}
deny=0.0.0.0/0.0.0.0
permit=127.0.0.1/255.255.255.255
read=system,call,log,verbose,command,agent,user,config,dtmf,reporting,cdr,dialplan
write=system,call,log,verbose,command,agent,user,config,reporting,originate
`;

  files["features.conf"] = `[general]
[featuremap]
[applicationmap]
`;

  files["pjsip.conf"] = `[global]
type=global
endpoint_identifier_order=username,ip,anonymous

[transport-udp]
type=transport
protocol=udp
bind=0.0.0.0:${sipPort}

[transport-ws]
type=transport
protocol=ws
bind=0.0.0.0:${wsPort}

[transport-wss]
type=transport
protocol=wss
bind=0.0.0.0:${wssPort}

${(v.endpoints ?? [])
  .map((ep) =>
    pjsipEndpointBlock({
      ext: ep.ext,
      name: ep.name,
      password: ep.password,
      webrtc: webrtcEndpoint(ep),
      context: "from-internal"
    })
  )
  .join("\n")}
${(cfg.intercoms ?? [])
  .filter((ic) => ic.intercom.sipExt && ic.intercom.sipPassword)
  .map((ic) =>
    pjsipEndpointBlock({
      ext: ic.intercom.sipExt!,
      name: ic.name,
      password: ic.intercom.sipPassword!,
      webrtc: false,
      context: doorContextName(ic)
    })
  )
  .join("\n")}
`;

  const ringContexts: string[] = [];
  const groupExtens: string[] = [];

  for (const ic of cfg.intercoms ?? []) {
    const groupId = ic.intercom.ringGroupId;
    if (!groupId) continue;
    const g = groupDial(cfg, groupId);
    if (!g) continue;
    const ctx = doorContextName(ic);
    const id = astSafe(ic.id);
    ringContexts.push(`[${ctx}]
exten => _X.,1,Goto(s,1)
exten => s,1,NoOp(Ring ${id})
 same => n,Set(__INTERCOM_ID=${id})
 same => n,UserEvent(Archie,Kind: ring,IntercomId: ${id})
 same => n,Dial(${g.dial},${g.timeout},tTU(archie-on-answer))
 same => n,UserEvent(Archie,Kind: cleared,IntercomId: ${id})
 same => n,Hangup()
`);
  }

  for (const g of v.groups ?? []) {
    const dial = groupDial(cfg, g.id);
    if (!dial) continue;
    groupExtens.push(`exten => ${astSafe(g.ext)},1,NoOp(Group ${astSafe(g.name)})
 same => n,Dial(${dial.dial},${dial.timeout},tT)
 same => n,Hangup()
`);
  }

  files["extensions.conf"] = `[general]
static=yes
writeprotect=yes

[from-internal]
${groupExtens.join("\n")}
exten => _X.,1,Dial(PJSIP/\${EXTEN},45)
 same => n,Hangup()

[archie-on-answer]
exten => s,1,UserEvent(Archie,Kind: answered,IntercomId: \${INTERCOM_ID})
 same => n,Return()

${ringContexts.join("\n")}
`;

  return files;
}

export function writeAsteriskConfig(cfg: HouseConfig): string {
  const dir = asteriskConfDir();
  fs.mkdirSync(dir, { recursive: true });
  const files = buildAsteriskFiles(cfg);
  for (const [name, body] of Object.entries(files)) {
    fs.writeFileSync(path.join(dir, name), body, "utf-8");
  }
  return dir;
}
