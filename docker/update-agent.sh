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
  ST_STATE=running ST_STEP=git ST_MESSAGE="Code ophalen van GitHub…" ST_REQUESTED_BY="$requested_by" ST_STARTED=1 ST_CLEAR_ERROR=1 write_status

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
      ST_STATE=running ST_STEP=git ST_MESSAGE="Koppelen aan GitHub…" write_status
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
    ST_STATE=running ST_STEP=git ST_MESSAGE="Code ophalen van GitHub…" write_status
    if apply_github_tarball "$branch" "$tok"; then
      code_ok=1
      log "tarball ok branch=$branch"
      ensure_git_origin || true
    fi
  fi

  if [ "$code_ok" -eq 0 ]; then
    restore_secrets
    ST_STATE=error ST_STEP=git ST_MESSAGE="GitHub ophalen mislukt. De NUC kan GitHub niet bereiken (netwerk) of de repo is privé zonder geldige GITHUB_TOKEN." ST_ERROR="git_fetch_failed" ST_FINISHED=1 write_status
    log "fail git_fetch_failed"
    return 1
  fi

  # GitHub is source of truth for code. house.json and docker/.env are restored after.
  restore_secrets
  log "code ok branch=$branch"

  ST_STATE=running ST_STEP=build ST_MESSAGE="Software bouwen. Dit duurt 10–20 minuten. Het huis blijft werken tot de herstart aan het eind." write_status

  if ! ( cd "$DOCKER_DIR" && $DOCKER compose --env-file .env up -d --build knx-stack >>"$LOG" 2>&1 ); then
    ST_STATE=error ST_STEP=build ST_MESSAGE="App bouwen/starten mislukt. Zie docker/data/update-agent.log op de NUC." ST_ERROR="compose_failed" ST_FINISHED=1 write_status
    log "fail compose_failed knx-stack"
    return 1
  fi
  if ! ( cd "$DOCKER_DIR" && $DOCKER compose --env-file .env up -d --build asterisk >>"$LOG" 2>&1 ); then
    log "warn asterisk compose failed (app is up)"
  fi

  ST_STATE=success ST_STEP= ST_MESSAGE="Server is bijgewerkt." ST_CLEAR_ERROR=1 ST_FINISHED=1 write_status
  log "update success"
  NEED_REEXEC=1
  return 0
}

log "agent start root=$ROOT"
if [ -d "$LOCK" ]; then
  rmdir "$LOCK" 2>/dev/null || true
  log "cleared stale lock"
fi
ST_STATE=idle ST_STEP= ST_MESSAGE="Wacht op update-opdracht." ST_CLEAR_TIMES=1 ST_CLEAR_ERROR=1 write_status

while true; do
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
  else
    heartbeat
  fi
  sleep 2
done
