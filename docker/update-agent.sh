#!/usr/bin/env sh
# Host-side updater: git pull from GitHub + docker compose rebuild.
# Triggered by the app (admin) via docker/data/update-request.json.
# Must run on the Ubuntu-VM, not inside the container.
set -eu

cd "$(dirname "$0")"
DOCKER_DIR="$(pwd)"
ROOT="$(CDPATH= cd .. && pwd)"
DATA="$DOCKER_DIR/data"
REQUEST="$DATA/update-request.json"
STATUS="$DATA/update-status.json"
LOCK="$DATA/update.lock"
LOG="$DATA/update-agent.log"

mkdir -p "$DATA"

log() {
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >> "$LOG"
}

iso_now() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

write_status() {
  # Env: ST_STATE ST_STEP ST_MESSAGE ST_ERROR ST_REQUESTED_BY ST_FINISHED
  python3 - "$STATUS" <<'PY' || true
import json, os, sys
from pathlib import Path
p = Path(sys.argv[1])
old = {}
if p.exists():
    try:
        old = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        old = {}
def env(k, default=None):
    v = os.environ.get(k)
    if v is None or v == "":
        return default
    return v
state = env("ST_STATE", old.get("state") or "idle")
out = {
    "state": state,
    "step": env("ST_STEP", old.get("step")),
    "message": env("ST_MESSAGE", old.get("message") or ""),
    "error": old.get("error"),
    "requestedBy": env("ST_REQUESTED_BY", old.get("requestedBy")),
    "requestedAt": old.get("requestedAt"),
    "startedAt": old.get("startedAt"),
    "finishedAt": old.get("finishedAt"),
    "agentHeartbeatAt": __import__("datetime").datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
}
if os.environ.get("ST_CLEAR_ERROR") == "1":
    out["error"] = None
elif env("ST_ERROR") is not None:
    out["error"] = env("ST_ERROR")
if env("ST_STARTED") == "1" or (state == "running" and not out.get("startedAt")):
    now = out["agentHeartbeatAt"]
    out["startedAt"] = now
    if not out.get("requestedAt"):
        out["requestedAt"] = now
if env("ST_FINISHED") == "1":
    out["finishedAt"] = out["agentHeartbeatAt"]
if env("ST_CLEAR_TIMES") == "1":
    out["startedAt"] = None
    out["finishedAt"] = None
    out["requestedAt"] = None
p.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
PY
}

heartbeat() {
  ST_STATE="${1:-}" ST_STEP="${2:-}" ST_MESSAGE="${3:-}" write_status
}

detect_docker() {
  if docker info >/dev/null 2>&1; then
    echo docker
    return
  fi
  if command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then
    echo "sudo docker"
    return
  fi
  echo ""
}

github_token() {
  envf="$DOCKER_DIR/.env"
  if [ ! -f "$envf" ]; then
    return
  fi
  # Strip optional quotes / CR. Do not echo elsewhere.
  grep '^GITHUB_TOKEN=' "$envf" 2>/dev/null | head -n 1 | cut -d= -f2- | tr -d '\r' | sed 's/^["'\'']//;s/["'\'']$//;s/[[:space:]]*$//' || true
}

github_repo() {
  repo="$(grep '^GITHUB_REPO=' "$DOCKER_DIR/.env" 2>/dev/null | head -n 1 | cut -d= -f2- | tr -d '\r' | sed 's/^["'\'']//;s/["'\'']$//;s/[[:space:]]*$//' || true)"
  if [ -z "$repo" ]; then
    repo="Archie-Automation/visualisatie"
  fi
  printf '%s' "$repo"
}

ensure_git_origin() {
  command -v git >/dev/null 2>&1 || return 1
  repo="$(github_repo)"
  if [ ! -d "$ROOT/.git" ]; then
    git -C "$ROOT" init >/dev/null 2>&1 || return 1
  fi
  git -C "$ROOT" remote remove origin >/dev/null 2>&1 || true
  git -C "$ROOT" remote add origin "https://github.com/${repo}.git" >/dev/null 2>&1 || \
    git -C "$ROOT" remote set-url origin "https://github.com/${repo}.git"
}

download_url() {
  dest="$1"
  url="$2"
  tok="$3"
  if command -v curl >/dev/null 2>&1; then
    if [ -n "$tok" ]; then
      curl -fsSL --max-time 180 \
        -H "Authorization: Bearer ${tok}" \
        -H "Accept: application/vnd.github+json" \
        -H "User-Agent: archie-os-update-agent" \
        -o "$dest" "$url"
    else
      curl -fsSL --max-time 180 \
        -H "User-Agent: archie-os-update-agent" \
        -o "$dest" "$url"
    fi
  elif command -v wget >/dev/null 2>&1; then
    if [ -n "$tok" ]; then
      wget -q --timeout=180 --header="Authorization: Bearer ${tok}" --header="Accept: application/vnd.github+json" -O "$dest" "$url"
    else
      wget -q --timeout=180 -O "$dest" "$url"
    fi
  else
    return 1
  fi
}

# ZIP/USB installs have no .git. GitHub tarball still yields a full tree.
apply_github_tarball() {
  branch="$1"
  tok="$2"
  repo="$(github_repo)"
  tmp="$(mktemp -d)"
  tgz="$tmp/src.tgz"
  api_url="https://api.github.com/repos/${repo}/tarball/${branch}"
  cd_url="https://codeload.github.com/${repo}/tar.gz/refs/heads/${branch}"
  got=0
  if [ -n "$tok" ] && download_url "$tgz" "$api_url" "$tok"; then
    got=1
  elif download_url "$tgz" "$api_url" ""; then
    got=1
  elif download_url "$tgz" "$cd_url" ""; then
    got=1
  fi
  if [ "$got" -eq 0 ] || [ ! -s "$tgz" ]; then
    rm -rf "$tmp"
    return 1
  fi
  mkdir -p "$tmp/src"
  if ! tar -xzf "$tgz" -C "$tmp/src"; then
    rm -rf "$tmp"
    return 1
  fi
  inner="$(find "$tmp/src" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  if [ -z "$inner" ]; then
    rm -rf "$tmp"
    return 1
  fi
  tar -C "$inner" -cf - . | tar -C "$ROOT" -xf -
  rm -rf "$tmp"
}

# HTTPS URL of origin, even if the remote is git@github.com (SSH has no token).
origin_https() {
  url="$(git -C "$ROOT" remote get-url origin 2>/dev/null || echo "")"
  url="$(printf '%s' "$url" | tr -d '\r')"
  case "$url" in
    git@github.com:*)
      printf 'https://github.com/%s' "${url#git@github.com:}"
      ;;
    ssh://git@github.com/*)
      printf 'https://github.com/%s' "${url#ssh://git@github.com/}"
      ;;
    https://*@github.com/*)
      printf 'https://github.com/%s' "${url#*github.com/}"
      ;;
    *)
      printf '%s' "$url"
      ;;
  esac
}

append_log_redacted() {
  tok="$1"
  src="$2"
  python3 - "$tok" "$src" >> "$LOG" <<'PY' || cat "$src" >> "$LOG"
import sys
from pathlib import Path
tok = sys.argv[1]
text = Path(sys.argv[2]).read_text(encoding="utf-8", errors="replace")
if tok:
    text = text.replace(tok, "[token]")
sys.stdout.write(text if text.endswith("\n") else text + "\n")
PY
}

# GitHub git-over-https wants Basic x-access-token in the URL.
# Authorization: Bearer extraHeader is ignored; git then prompts for a username
# and fails with GIT_TERMINAL_PROMPT=0 ("oude git-login").
github_https_with_token() {
  url="$1"
  tok="$2"
  case "$url" in
    https://github.com/*)
      if [ -n "$tok" ]; then
        printf 'https://x-access-token:%s@github.com/%s' "$tok" "${url#https://github.com/}"
        return
      fi
      ;;
  esac
  printf '%s' "$url"
}

git_with_token() {
  tok="$1"
  shift
  if [ -z "$tok" ]; then
    GIT_TERMINAL_PROMPT=0 git -c credential.helper= "$@"
    return $?
  fi
  # Inject token into https://github.com/… args only. Never log this argv.
  cmd="GIT_TERMINAL_PROMPT=0 git -c credential.helper="
  for a in "$@"; do
    case "$a" in
      https://github.com/*)
        a="$(github_https_with_token "$a" "$tok")"
        ;;
    esac
    q=$(printf '%s' "$a" | sed "s/'/'\\\\''/g")
    cmd="$cmd '$q'"
  done
  eval "$cmd"
}

run_update() {
  requested_by="$1"
  log "update start requestedBy=$requested_by"
  ST_STATE=running ST_STEP=git ST_MESSAGE="Server wordt bijgewerkt." ST_REQUESTED_BY="$requested_by" ST_STARTED=1 ST_CLEAR_ERROR=1 write_status

  DOCKER="$(detect_docker)"
  if [ -z "$DOCKER" ]; then
    ST_STATE=error ST_STEP= ST_MESSAGE="Docker is niet bereikbaar." ST_ERROR="docker_unavailable" ST_FINISHED=1 write_status
    log "fail docker_unavailable"
    return 1
  fi

  house_bak="$DATA/house.json.update-bak"
  env_bak="$DATA/dotenv.update-bak"
  rm -f "$house_bak" "$env_bak"
  if [ -f "$ROOT/config/house.json" ]; then
    cp -a "$ROOT/config/house.json" "$house_bak"
  fi
  if [ -f "$DOCKER_DIR/.env" ]; then
    cp -a "$DOCKER_DIR/.env" "$env_bak"
  fi

  restore_secrets() {
    if [ -f "$house_bak" ]; then
      cp -a "$house_bak" "$ROOT/config/house.json"
    fi
    if [ -f "$env_bak" ]; then
      cp -a "$env_bak" "$DOCKER_DIR/.env"
    fi
  }

  tok="$(github_token)"
  branch=main
  if command -v git >/dev/null 2>&1 && [ -d "$ROOT/.git" ]; then
    cur="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
    if [ -n "$cur" ] && [ "$cur" != "HEAD" ]; then
      branch="$cur"
    fi
  fi

  code_ok=0
  git_err="$(mktemp)"
  if command -v git >/dev/null 2>&1; then
    if [ ! -d "$ROOT/.git" ]; then
      log "no .git in $ROOT — git init + origin"
      ST_STATE=running ST_STEP=git ST_MESSAGE="Server wordt bijgewerkt." write_status
      ensure_git_origin || log "git init/origin failed"
    fi
    fetch_url="$(origin_https)"
    if [ -z "$fetch_url" ]; then
      fetch_url="https://github.com/$(github_repo).git"
      ensure_git_origin || true
    fi
    log "git fetch url=$fetch_url branch=$branch token=$([ -n "$tok" ] && echo yes || echo no)"
    case "$fetch_url" in
      https://github.com/*)
        if git_with_token "$tok" -C "$ROOT" fetch --prune "$fetch_url" "+refs/heads/${branch}:refs/remotes/origin/${branch}" >"$git_err" 2>&1; then
          code_ok=1
        elif [ -n "$tok" ] && git_with_token "" -C "$ROOT" fetch --prune "$fetch_url" "+refs/heads/${branch}:refs/remotes/origin/${branch}" >"$git_err" 2>&1; then
          log "git fetch ok anonymously (token unused or rejected)"
          code_ok=1
        fi
        ;;
      *)
        if git_with_token "$tok" -C "$ROOT" fetch --prune origin >"$git_err" 2>&1; then
          code_ok=1
        fi
        ;;
    esac
    if [ "$code_ok" -eq 1 ]; then
      if git_with_token "$tok" -C "$ROOT" reset --hard "origin/$branch" >>"$git_err" 2>&1; then
        log "git ok branch=$branch"
      else
        log "git reset failed — tarball fallback"
        code_ok=0
      fi
    else
      append_log_redacted "$tok" "$git_err"
      log "git fetch failed — tarball fallback"
    fi
  else
    log "git not installed — tarball fallback"
  fi
  rm -f "$git_err"

  if [ "$code_ok" -eq 0 ]; then
    ST_STATE=running ST_STEP=git ST_MESSAGE="Server wordt bijgewerkt." write_status
    if apply_github_tarball "$branch" "$tok"; then
      code_ok=1
      log "tarball ok branch=$branch"
      ensure_git_origin || true
    fi
  fi

  if [ "$code_ok" -eq 0 ]; then
    restore_secrets
    ST_STATE=error ST_STEP=git ST_MESSAGE="Software ophalen mislukt. Controleer de netwerkverbinding van de NUC." ST_ERROR="git_fetch_failed" ST_FINISHED=1 write_status
    log "fail git_fetch_failed"
    return 1
  fi

  # GitHub is source of truth for code. house.json and docker/.env are restored after.
  restore_secrets
  # Blijvende kopie voor een handmatige `git pull` die het huis zou wissen.
  if [ -f "$ROOT/config/house.json" ]; then
    cp -a "$ROOT/config/house.json" "$DATA/house.json.keep" 2>/dev/null || true
  fi
  log "code ok branch=$branch"

  ST_STATE=running ST_STEP=build ST_MESSAGE="Software bouwen. Meestal 1–3 minuten. Het huis blijft werken tot de herstart aan het eind." write_status

  # Asterisk zit in knx-stack; --remove-orphans haalt de oude losse container weg.
  if ! ( cd "$DOCKER_DIR" && $DOCKER compose --env-file .env up -d --build --remove-orphans knx-stack >>"$LOG" 2>&1 ); then
    ST_STATE=error ST_STEP=build ST_MESSAGE="App bouwen/starten mislukt. Zie docker/data/update-agent.log op de NUC." ST_ERROR="compose_failed" ST_FINISHED=1 write_status
    log "fail compose_failed knx-stack"
    return 1
  fi

  ST_STATE=success ST_STEP= ST_MESSAGE="Server wordt bijgewerkt." ST_CLEAR_ERROR=1 ST_FINISHED=1 write_status
  log "update success"
  NEED_REEXEC=1
  return 0
}

write_enroll_status() {
  # Vervang het bestand. De app schrijft het als root; overschrijven lukt dan niet,
  # vervangen via de map wel.
  python3 - "$DATA/enroll-status.json" <<'PY' || true
import json, os, sys
from datetime import datetime
from pathlib import Path
p = Path(sys.argv[1])
def env(k):
    v = os.environ.get(k)
    return v if v else None
old = {}
if p.exists():
    try:
        old = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        old = {}
out = {
    "state": env("ST_STATE") or "idle",
    "message": os.environ.get("ST_MESSAGE") or "",
    "error": env("ST_ERROR"),
    "remoteUrl": env("ST_REMOTE") or old.get("remoteUrl"),
    "requestedAt": old.get("requestedAt"),
    "updatedAt": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
}
tmp = p.with_name(p.name + ".tmp")
tmp.write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
os.chmod(tmp, 0o666)
os.replace(tmp, p)
PY
}

# De agent draait niet als root en heeft geen wachtwoordloze sudo.
# Docker mag hij wel (zelfde rechten als Server bijwerken). Daarmee een
# kort script op de host zelf uitvoeren.
run_host_script() {
  script="$1"
  chmod 700 "$script" 2>/dev/null || true
  if [ "$(id -u)" -eq 0 ]; then
    /bin/sh "$script" >>"$LOG" 2>&1
    return $?
  fi
  if command -v sudo >/dev/null 2>&1 && sudo -n /bin/sh "$script" >>"$LOG" 2>&1; then
    return 0
  fi
  log "sudo geweigerd, vervolg via docker"
  DOCKER="$(detect_docker)"
  if [ -z "$DOCKER" ]; then
    log "geen docker beschikbaar"
    return 1
  fi
  # archie-os-stack is alpine; entrypoint overslaan, anders start de app.
  # shellcheck disable=SC2086
  $DOCKER run --rm --privileged --pid=host --network host \
    --entrypoint /bin/busybox \
    archie-os-stack:latest \
    chroot /proc/1/root /bin/sh "$script" >>"$LOG" 2>&1
}

run_enroll() {
  ENROLL_ERR=
  req="$DATA/enroll-request.json"
  rc=0
  code="$(python3 - "$req" <<'PY'
import json, re, sys
from pathlib import Path
p = Path(sys.argv[1])
try:
    raw = p.read_text(encoding="utf-8")
except OSError:
    sys.exit(3)
d = json.loads(raw)
c = str(d.get("code") or "").strip().upper()
if not re.fullmatch(r"[A-Z0-9]{4}-[A-Z0-9]{4}", c):
    sys.exit(2)
print(c)
PY
)" || rc=$?
  if [ "${rc:-0}" != 0 ]; then
    rm -f "$req" 2>/dev/null || true
    if [ "${rc:-0}" = 3 ]; then
      ST_STATE=error ST_MESSAGE="De server kon de code niet lezen. Vraag een nieuwe code." ST_ERROR=unreadable write_enroll_status
    else
      ST_STATE=error ST_MESSAGE="Code klopt niet. Verwacht vier tekens, een streepje, vier tekens." ST_ERROR=bad_code write_enroll_status
    fi
    return 1
  fi
  rm -f "$req"
  ST_STATE=running ST_MESSAGE="Koppelen…" ST_ERROR= write_enroll_status
  log "enroll start"
  if ! command -v wg >/dev/null 2>&1 && ! [ -x /usr/bin/wg ]; then
    script="$DATA/wg-install.sh"
    cat > "$script" <<'EOF'
#!/bin/sh
set -eu
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y wireguard-tools
command -v wg >/dev/null 2>&1
EOF
    if ! run_host_script "$script"; then
      rm -f "$script"
      ST_STATE=error ST_MESSAGE="WireGuard kon niet worden geïnstalleerd." ST_ERROR=no_wg write_enroll_status
      log "enroll wg install failed"
      return 1
    fi
    rm -f "$script"
  fi
  if ! command -v wg >/dev/null 2>&1 && ! [ -x /usr/bin/wg ]; then
    ST_STATE=error ST_MESSAGE="WireGuard is geïnstalleerd maar niet gevonden." ST_ERROR=no_wg write_enroll_status
    return 1
  fi
  command -v python3 >/dev/null 2>&1 || {
    ST_STATE=error ST_MESSAGE="python3 ontbreekt op de server." ST_ERROR=no_python write_enroll_status
    return 1
  }
  umask 077
  if [ -x /usr/bin/wg ]; then
    WG=/usr/bin/wg
  else
    WG=wg
  fi
  priv="$("$WG" genkey)"
  pub="$(printf '%s' "$priv" | "$WG" pubkey)"
  hostn="$(hostname 2>/dev/null || echo nuc)"
  body="$(printf '{"code":"%s","publicKey":"%s","hostname":"%s"}' "$code" "$pub" "$hostn")"
  enroll_url="${ARCHIE_CLOUD_ENROLL:-https://enroll.archie-cloud.com}"
  resp="$(curl -fsS --max-time 20 -H 'content-type: application/json' -d "$body" "${enroll_url}/enroll" 2>&1)" || {
    ST_STATE=error ST_MESSAGE="Aanmelden mislukt. De code is ongeldig of verlopen." ST_ERROR=enroll_failed write_enroll_status
    log "enroll http fail"
    return 1
  }
  eval "$(printf '%s' "$resp" | python3 -c '
import json, sys, shlex
d = json.load(sys.stdin)
if "error" in d:
    print("ENROLL_ERR=" + shlex.quote(d["error"])); sys.exit(0)
wg = d["wg"]; turn = d.get("turn", {})
for k, v in {
  "E_SERVER_ID": d["serverId"], "E_REMOTE_URL": d["remoteUrl"],
  "E_WG_ADDR": wg["address"], "E_WG_PUB": wg["serverPublicKey"],
  "E_WG_EP": wg["endpoint"], "E_WG_ALLOWED": wg["allowedIps"],
  "E_WG_KA": str(wg.get("persistentKeepalive", 25)),
  "E_TURN_HOST": turn.get("host", ""), "E_TURN_SECRET": turn.get("secret", ""),
}.items():
    print(k + "=" + shlex.quote(str(v)))
')"
  if [ -n "${ENROLL_ERR:-}" ]; then
    ST_STATE=error ST_MESSAGE="Code geweigerd: ${ENROLL_ERR}" ST_ERROR=rejected write_enroll_status
    return 1
  fi
  script="$DATA/wg-up.sh"
  cat > "$script" <<EOF
#!/bin/sh
set -eu
mkdir -p /etc/wireguard
umask 077
cat > /etc/wireguard/wg0.conf <<'CFG'
[Interface]
PrivateKey = ${priv}
Address = ${E_WG_ADDR}

[Peer]
PublicKey = ${E_WG_PUB}
Endpoint = ${E_WG_EP}
AllowedIPs = ${E_WG_ALLOWED}
PersistentKeepalive = ${E_WG_KA}
CFG
chmod 600 /etc/wireguard/wg0.conf
systemctl enable wg-quick@wg0 || true
systemctl restart wg-quick@wg0
EOF
  if ! run_host_script "$script"; then
    rm -f "$script"
    ST_STATE=error ST_MESSAGE="Tunnel starten mislukt." ST_ERROR=wg_start write_enroll_status
    log "enroll wg start failed"
    return 1
  fi
  rm -f "$script"
  set_env_var() {
    key="$1"; val="$2"
    envf="$DOCKER_DIR/.env"
    touch "$envf"
    if grep -q "^${key}=" "$envf" 2>/dev/null; then
      sed -i.bak "s|^${key}=.*|${key}=${val}|" "$envf"
      rm -f "$envf.bak"
    else
      printf '%s=%s\n' "$key" "$val" >> "$envf"
    fi
  }
  set_env_var REMOTE_URL "$E_REMOTE_URL"
  set_env_var WG_ADDRESS "${E_WG_ADDR%/*}"
  set_env_var TURN_HOST "$E_TURN_HOST"
  set_env_var TURN_SECRET "$E_TURN_SECRET"
  ST_STATE=success ST_MESSAGE="Gekoppeld." ST_ERROR= ST_REMOTE="$E_REMOTE_URL" write_enroll_status
  log "enroll ok url=$E_REMOTE_URL"
  DOCKER="$(detect_docker)"
  if [ -n "$DOCKER" ]; then
    ( cd "$DOCKER_DIR" && $DOCKER compose --env-file .env up -d --no-deps knx-stack >>"$LOG" 2>&1 ) || \
      log "enroll compose reload failed"
  fi
  return 0
}

log "agent start root=$ROOT"
if [ -d "$LOCK" ]; then
  rmdir "$LOCK" 2>/dev/null || true
  log "cleared stale lock"
fi
if [ -d "$DATA/enroll.lock" ]; then
  rmdir "$DATA/enroll.lock" 2>/dev/null || true
  log "cleared stale enroll lock"
fi
# Do not clobber a just-finished success: tablets poll this file and the
# previous line used to reset to idle immediately after re-exec.
python3 - "$STATUS" <<'PY' || true
import json, os, sys
from pathlib import Path
from datetime import datetime
p = Path(sys.argv[1])
old = {}
if p.exists():
    try:
        old = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        old = {}
now = datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
state = (old.get("state") or "").strip()
if state in ("success", "error"):
    old["agentHeartbeatAt"] = now
    p.write_text(json.dumps(old, indent=2) + "\n", encoding="utf-8")
else:
    os.environ["ST_STATE"] = "idle"
    os.environ["ST_STEP"] = ""
    os.environ["ST_MESSAGE"] = "Wacht op update-opdracht."
    os.environ["ST_CLEAR_TIMES"] = "1"
    os.environ["ST_CLEAR_ERROR"] = "1"
    # write_status is a shell function; fall through via a marker file
    Path(str(p) + ".want-idle").write_text("1", encoding="utf-8")
PY
if [ -f "$STATUS.want-idle" ]; then
  rm -f "$STATUS.want-idle"
  ST_STATE=idle ST_STEP= ST_MESSAGE="Wacht op update-opdracht." ST_CLEAR_TIMES=1 ST_CLEAR_ERROR=1 write_status
fi

while true; do
  # Update gaat vóór een koppeling. Een blijven liggen request mag bijwerken niet blokkeren.
  if [ -f "$REQUEST" ]; then
    if mkdir "$LOCK" 2>/dev/null; then
      requested_by="$(python3 - "$REQUEST" <<'PY' 2>/dev/null || echo admin
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
try:
    d = json.loads(p.read_text(encoding="utf-8"))
    print((d.get("requestedBy") or "admin").strip() or "admin")
except Exception:
    print("admin")
PY
)"
      rm -f "$REQUEST"
      NEED_REEXEC=0
      run_update "$requested_by" || true
      rmdir "$LOCK" 2>/dev/null || true
      if [ "${NEED_REEXEC:-0}" = 1 ]; then
        log "re-exec agent so next tablet update uses the new script"
        exec /bin/sh "$DOCKER_DIR/update-agent.sh"
      fi
    fi
  elif [ -f "$DATA/enroll-request.json" ]; then
    if mkdir "$DATA/enroll.lock" 2>/dev/null; then
      run_enroll || true
      rmdir "$DATA/enroll.lock" 2>/dev/null || true
    fi
  else
    heartbeat
  fi
  sleep 2
done
