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
  # Strip optional quotes. Do not echo elsewhere.
  grep '^GITHUB_TOKEN=' "$envf" 2>/dev/null | head -n 1 | cut -d= -f2- | tr -d '\r' | sed 's/^["'\'']//;s/["'\'']$//' || true
}

git_with_token() {
  tok="$1"
  shift
  if [ -n "$tok" ]; then
    git -c "http.extraHeader=Authorization: Bearer $tok" "$@"
  else
    git "$@"
  fi
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
  branch="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
  if [ "$branch" = "HEAD" ] || [ -z "$branch" ]; then
    branch=main
  fi

  if ! git_with_token "$tok" -C "$ROOT" fetch origin; then
    restore_secrets
    ST_STATE=error ST_STEP=git ST_MESSAGE="GitHub ophalen mislukt (token of netwerk)." ST_ERROR="git_fetch_failed" ST_FINISHED=1 write_status
    log "fail git_fetch_failed"
    return 1
  fi

  # GitHub is source of truth for code. house.json and docker/.env are restored after.
  if ! git_with_token "$tok" -C "$ROOT" reset --hard "origin/$branch"; then
    restore_secrets
    ST_STATE=error ST_STEP=git ST_MESSAGE="Git reset mislukt." ST_ERROR="git_reset_failed" ST_FINISHED=1 write_status
    log "fail git_reset_failed"
    return 1
  fi
  restore_secrets
  log "git ok branch=$branch"

  ST_STATE=running ST_STEP=build ST_MESSAGE="Software bouwen. Dit duurt 10–20 minuten. Het huis blijft werken tot de herstart aan het eind." write_status

  if ! ( cd "$DOCKER_DIR" && $DOCKER compose --env-file .env up -d --build ); then
    ST_STATE=error ST_STEP=build ST_MESSAGE="Bouwen of starten mislukt. Zie update-agent.log op de NUC." ST_ERROR="compose_failed" ST_FINISHED=1 write_status
    log "fail compose_failed"
    return 1
  fi

  ST_STATE=success ST_STEP= ST_MESSAGE="Server is bijgewerkt." ST_CLEAR_ERROR=1 ST_FINISHED=1 write_status
  log "update success"
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
      run_update "$requested_by" || true
      rmdir "$LOCK" 2>/dev/null || true
    fi
  else
    heartbeat
  fi
  sleep 2
done
