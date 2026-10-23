#!/usr/bin/env bash
# Local "new instance" sandbox: a FRESH Postgres 18 (Docker) + Alembic migrations + the
# new-instance seed, plus the backend and Next.js frontend wired to it.
#
#   ./scripts/local-new-instance.sh up         # db → migrate → seed (idempotent, re-runnable)
#   ./scripts/local-new-instance.sh backend    # FastAPI on :8001  (foreground, --reload)
#   ./scripts/local-new-instance.sh frontend   # Next.js on :3001  (foreground)
#   ./scripts/local-new-instance.sh status     # what is running / how far the DB got
#   ./scripts/local-new-instance.sh psql       # shell into the sandbox DB
#   ./scripts/local-new-instance.sh reset      # DESTROY the sandbox DB (container + volume)
#
# `backend` uses the backend's OWN dev DB by default (whatever backend/ resolves with no override —
# localhost:5433/hrms_dev unless DATABASE_URL is set in your env/.env). Add -s/--sandbox (or
# DB_TARGET=sandbox) to run it against the throwaway sandbox DB instead. db/migrate/seed/up/psql/
# reset only ever manage the sandbox container, never the dev DB.
#
# Which HRMS clone it drives is configurable (default: workspace-2/hrms, where HRMS changes are made):
#   ./scripts/local-new-instance.sh -s backend             # backend on the sandbox DB
#   ./scripts/local-new-instance.sh -w workspace-1 up      # -w/--workspace <name under the oyehr root>
#   HRMS_WORKSPACE=workspace-1 ./scripts/local-new-instance.sh up
#   HRMS_DIR=/abs/path/to/hrms ./scripts/local-new-instance.sh up   # any checkout; beats the above
#
# Everything is local and isolated from the other stacks on this machine: its own container
# (hrms-newinst-db), volume, host port (5434), backend port (8001) and frontend port (3001).
# In sandbox mode config reaches the apps as real env vars, which beat backend/.env AND
# backend/.env.local (the latter points at the REMOTE hrms-dev DB — never read or edited here).
# Open http://localhost:3001/login?subdomain=super and sign in as the seeded Server Admin.
set -euo pipefail

OYEHR_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Leading flags (any order): -w/--workspace <name> picks the clone (a directory under the oyehr
# root holding hrms/); -s/--sandbox points the backend at the sandbox DB instead of its dev DB.
DB_TARGET="${DB_TARGET:-dev}"
while [ $# -gt 0 ]; do
  case "$1" in
    -w|--workspace)
      [ -n "${2:-}" ] || { echo "$1 needs a workspace name, e.g. workspace-1." >&2; exit 1; }
      HRMS_WORKSPACE="$2"; shift 2 ;;
    -s|--sandbox) DB_TARGET=sandbox; shift ;;
    *) break ;;
  esac
done
HRMS_WORKSPACE="${HRMS_WORKSPACE:-workspace-2}"
HRMS_DIR="${HRMS_DIR:-$OYEHR_ROOT/$HRMS_WORKSPACE/hrms}"
ROOT="$(cd "$HRMS_DIR" 2>/dev/null && pwd)" || {
  echo "HRMS working copy not found at ${HRMS_DIR} — check -w/HRMS_WORKSPACE/HRMS_DIR." >&2; exit 1; }
[ -d "$ROOT/backend" ] && [ -d "$ROOT/frontend" ] || {
  echo "${ROOT} has no backend/ and frontend/ — check -w/HRMS_WORKSPACE/HRMS_DIR." >&2; exit 1; }
CONTAINER="${NEWINST_DB_CONTAINER:-hrms-newinst-db}"
VOLUME="${NEWINST_DB_VOLUME:-hrms_newinst_pgdata}"
DB_PORT="${NEWINST_DB_PORT:-5434}"
API_PORT="${NEWINST_API_PORT:-8001}"
WEB_PORT="${NEWINST_WEB_PORT:-3001}"
DB_NAME="${NEWINST_DB_NAME:-hrms_newinst}"
DATABASE_URL="postgresql+psycopg://hrms:hrms@localhost:${DB_PORT}/${DB_NAME}"

# Local-only Server Admin credentials (throwaway sandbox) — override via env.
export SEED_ADMIN_FIRST_NAME="${SEED_ADMIN_FIRST_NAME:-Server}"
export SEED_ADMIN_LAST_NAME="${SEED_ADMIN_LAST_NAME:-Admin}"
export SEED_ADMIN_EMAIL="${SEED_ADMIN_EMAIL:-admin@localhost.test}"
export SEED_ADMIN_MOBILE="${SEED_ADMIN_MOBILE:-9999999999}"
export SEED_ADMIN_PASSWORD="${SEED_ADMIN_PASSWORD:-LocalAdmin#2026}"

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
psql_in() { docker exec -i "$CONTAINER" psql -v ON_ERROR_STOP=1 -U postgres "$@"; }

# The DB the backend itself resolves (password hidden), run from backend/ with the caller's env.
dev_db_target() {
  ( cd "$ROOT/backend" && uv run python -c \
    'from app.core.config import settings; from sqlalchemy.engine import make_url; print(make_url(settings.database_url).render_as_string(hide_password=True))' \
    2>/dev/null ) || echo "unresolved"
}

need_docker() {
  docker info >/dev/null 2>&1 || { echo "Docker is not running — start Docker Desktop first." >&2; exit 1; }
}

cmd_db() {
  need_docker
  say "Postgres 18 on localhost:${DB_PORT} (container ${CONTAINER})"
  if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    docker start "$CONTAINER" >/dev/null
  else
    if lsof -nP -iTCP:"$DB_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
      echo "Port ${DB_PORT} is already in use — set NEWINST_DB_PORT to a free port." >&2; exit 1
    fi
    docker run -d --name "$CONTAINER" -e POSTGRES_PASSWORD=postgres \
      -p "127.0.0.1:${DB_PORT}:5432" -v "${VOLUME}:/var/lib/postgresql" postgres:18 >/dev/null
  fi
  for _ in $(seq 1 60); do
    docker exec "$CONTAINER" pg_isready -U postgres >/dev/null 2>&1 && break; sleep 1
  done
  docker exec "$CONTAINER" pg_isready -U postgres >/dev/null || { echo "Postgres did not become ready" >&2; exit 1; }
  # Same shape as infra/docker/initdb.sql: `hrms` is a NORMAL (non-superuser) role. Idempotent.
  psql_in -q <<SQL
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'hrms') THEN
    CREATE ROLE hrms LOGIN PASSWORD 'hrms';
  END IF;
END \$\$;
SELECT 'CREATE DATABASE ${DB_NAME} OWNER hrms'
 WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_NAME}')\gexec
SQL
  echo "ready: ${DATABASE_URL}"
}

cmd_migrate() {
  say "Alembic migrations (device_commands branch first, then every head)"
  ( cd "$ROOT/backend"
    export DATABASE_URL ENABLE_SCHEDULER=false
    uv run python scripts/migrate.py upgrade c3f8d21a9e47
    uv run python scripts/migrate.py upgrade heads
    uv run python scripts/migrate.py current )
}

cmd_seed() {
  say "Seed new instance: Server Admin + super domain (reference data came with the migration)"
  # The Alembic data revision already loaded the reference data (CDPs exist after `migrate`),
  # so "seeded" means a Server Admin login exists, not that CDPs exist.
  local n
  n="$(docker exec "$CONTAINER" psql -U postgres -d "$DB_NAME" -tAc \
        'SELECT count(*) FROM user_role_details' 2>/dev/null || echo "")"
  if [ -z "$n" ]; then echo "Schema is missing — run '$0 migrate' first." >&2; exit 1; fi
  if [ "$n" != "0" ]; then
    echo "Already seeded (${n} memberships) — skipping. Use '$0 reset' then '$0 up' for a clean slate."
    return 0
  fi
  ( cd "$ROOT/backend"
    export DATABASE_URL ENABLE_SCHEDULER=false
    uv run python scripts/seed_new_instance.py --apply )
  echo
  echo "Server Admin → ${SEED_ADMIN_EMAIL} / ${SEED_ADMIN_PASSWORD}  (host 'super')"
}

cmd_up() { cmd_db; cmd_migrate; cmd_seed; cmd_status; }

cmd_backend() {
  cd "$ROOT/backend"
  export ENABLE_SCHEDULER=false ENVIRONMENT=development LOG_LEVEL=INFO \
    CORS_ORIGINS="http://localhost:${WEB_PORT},http://127.0.0.1:${WEB_PORT}" \
    PUBLIC_APP_URL="http://localhost:${WEB_PORT}"
  if [ "$DB_TARGET" = "sandbox" ]; then
    export DATABASE_URL
    say "Backend on http://localhost:${API_PORT}  (DB: sandbox localhost:${DB_PORT}/${DB_NAME})"
  else
    # No DATABASE_URL override: the backend resolves its own dev DB from its settings/env.
    say "Backend on http://localhost:${API_PORT}  (DB: dev — $(dev_db_target))"
  fi
  exec uv run uvicorn app.main:app --host 127.0.0.1 --port "$API_PORT" --reload
}

cmd_frontend() {
  say "Frontend on http://localhost:${WEB_PORT}  (API: http://localhost:${API_PORT})"
  cd "$ROOT/frontend"
  [ -d node_modules ] || npm install
  # Real env vars; `next dev` run directly so frontend/.env.dev (remote dev URLs) is not loaded.
  export NEXT_PUBLIC_API_URL="http://localhost:${API_PORT}" NEXT_PUBLIC_SHARED_HOSTS="" \
    NEXT_PUBLIC_OYEHR_HOSTS=""
  echo "Open http://localhost:${WEB_PORT}/login?subdomain=super"
  exec npx next dev --turbopack -p "$WEB_PORT"
}

cmd_status() {
  say "Status  (HRMS: ${ROOT})"
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER"; then
    echo "db        : running  localhost:${DB_PORT}/${DB_NAME}"
    docker exec "$CONTAINER" psql -U postgres -d "$DB_NAME" -tAc \
      "SELECT 'cdps=' || (SELECT count(*) FROM care_delivery_program_masters) || ' users=' || (SELECT count(*) FROM users) || ' admin_logins=' || (SELECT count(*) FROM user_role_details)" \
      2>/dev/null | sed 's/^/seeded    : /' || echo "seeded    : (schema not migrated yet)"
  else
    echo "db        : not running"
  fi
  echo "backend db: ${DB_TARGET} ($([ "$DB_TARGET" = sandbox ] && echo "localhost:${DB_PORT}/${DB_NAME}" || dev_db_target))"
  curl -fsS -o /dev/null "http://localhost:${API_PORT}/healthz" 2>/dev/null \
    && echo "backend   : up   http://localhost:${API_PORT}" || echo "backend   : down"
  curl -fsS -o /dev/null "http://localhost:${WEB_PORT}" 2>/dev/null \
    && echo "frontend  : up   http://localhost:${WEB_PORT}/login?subdomain=super" || echo "frontend  : down"
}

cmd_psql() { need_docker; exec docker exec -it "$CONTAINER" psql -U hrms -d "$DB_NAME"; }

cmd_reset() {
  need_docker
  say "Destroying the sandbox DB (container ${CONTAINER} + volume ${VOLUME})"
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  docker volume rm "$VOLUME" >/dev/null 2>&1 || true
  echo "done."
}

case "${1:-}" in
  up) cmd_up ;; db) cmd_db ;; migrate) cmd_migrate ;; seed) cmd_seed ;;
  backend) cmd_backend ;; frontend) cmd_frontend ;; status) cmd_status ;;
  psql) cmd_psql ;; reset) cmd_reset ;;
  *) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
