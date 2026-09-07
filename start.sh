#!/usr/bin/env bash
#===============================================================================
# start.sh — Arranca Shopify Manager (backend + frontend).
#
# Uso:
#   ./start.sh                  # modo local (desarrollo), servidores con hot reload
#   ./start.sh --lan            # accesible desde la red local (IP auto-detectada)
#   ./start.sh --external URL   # accesible externamente (dominio/túnel)
#   ./start.sh --docker         # levanta contenedores Docker (dev)
#   ./start.sh --docker --prod  # contenedores Docker de producción
#   ./start.sh --backend-only   # arranca solo el backend
#   ./start.sh --frontend-only  # arranca solo el frontend
#   ./start.sh --seed           # carga datos de demostración antes de arrancar
#   ./start.sh --stop           # detiene los servidores en segundo plano
#
# En modo local los procesos se ejecutan en segundo plano y escriben logs en logs/.
#===============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT_DIR/.env"
LOG_DIR="$ROOT_DIR/logs"
PID_FILE="$ROOT_DIR/logs/pids.txt"
mkdir -p "$LOG_DIR"

MODE="local"
DOCKER_MODE=false
PROD=false
LAN=false
EXTERNAL_URL=""
BACKEND_ONLY=false
FRONTEND_ONLY=false
DO_SEED=false
STOP=false
WHO_SERVICE_PROVIDER="both"

for arg in "$@"; do
  case "$arg" in
    --lan) LAN=true; MODE="lan" ;;
    --external) MODE="external" ;;
    --docker) DOCKER_MODE=true ;;
    --prod) PROD=true ;;
    --backend-only) BACKEND_ONLY=true; WHO_SERVICE_PROVIDER="backend" ;;
    --frontend-only) FRONTEND_ONLY=true; WHO_SERVICE_PROVIDER="frontend" ;;
    --seed) DO_SEED=true ;;
    --stop) STOP=true ;;
    --help|-h)
      sed -n '2,17p' "$0"
      exit 0
      ;;
    *)
      # --external URL
      if [[ "$arg" == --external=* ]]; then
        EXTERNAL_URL="${arg#*=}"; MODE="external"
      elif $LAN && [ -z "$EXTERNAL_URL" ] && [[ "$arg" == http* ]]; then
        EXTERNAL_URL="$arg"; MODE="external"
      else
        echo "⚠ Argumento desconocido: $arg"
      fi
      ;;
  esac
done

say()  { printf '\033[1;34m◆\033[0m %s\n' "$1"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m⚠\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$1" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

#------------------------------------------------------------------------------
# Detección de IP local (para modo LAN)
#------------------------------------------------------------------------------
detect_ip() {
  if have hostname; then
    local ip
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')" || true
    if [ -n "$ip" ]; then echo "$ip"; return; fi
  fi
  if have ip; then
    local ip2
    ip2="$(ip route get 1 2>/dev/null | awk '{print $NF; exit}')" || true
    if [ -n "$ip2" ]; then echo "$ip2"; return; fi
  fi
  echo "localhost"
}

set_env() {
  local key="$1" val="$2"
  if grep -q "^$key=" "$ENV_FILE"; then
    sed -i "s|^$key=.*|$key=$val|" "$ENV_FILE"
  else
    echo "$key=$val" >> "$ENV_FILE"
  fi
}

#------------------------------------------------------------------------------
# Detener procesos en segundo plano
#------------------------------------------------------------------------------
stop_local() {
  if [ -f "$PID_FILE" ]; then
    say "Deteniendo procesos…"
    while IFS= read -r pid; do
      [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    done < "$PID_FILE"
    rm -f "$PID_FILE"
    ok "Servidores detenidos."
  else
    warn "No hay procesos registrados en $PID_FILE."
  fi
  # Limpieza adicional
  pkill -f "ts-node-dev.*src/index.ts" 2>/dev/null || true
  pkill -f "next dev" 2>/dev/null || true
  pkill -f "next-server" 2>/dev/null || true
}

if $STOP; then
  stop_local
  exit 0
fi

#------------------------------------------------------------------------------
# .env base
#------------------------------------------------------------------------------
[ -f "$ENV_FILE" ] || { warn "No existe .env. Ejecuta primero: ./install.sh"; }

#------------------------------------------------------------------------------
# Modo Docker
#------------------------------------------------------------------------------
if $DOCKER_MODE; then
  if $DO_SEED; then
    say "El seed en modo Docker se ejecuta dentro del contenedor del backend:"
    warn "docker exec -it shopify_manager_backend npx ts-node --transpile-only prisma/seed.ts"
  fi

  if $PROD; then
    say "Arrancando contenedores de PRODUCCIÓN…"
    if [ "$MODE" = "lan" ] || [ "$MODE" = "external" ]; then
      IP="$(detect_ip)"
      if [ -z "$EXTERNAL_URL" ]; then EXTERNAL_URL="http://$IP"; fi
      set_env APP_URL "$EXTERNAL_URL"
      set_env BACKEND_URL "$EXTERNAL_URL/api"
      set_env WEBHOOK_URL "$EXTERNAL_URL/webhooks"
      set_env NEXT_PUBLIC_API_URL "$EXTERNAL_URL/api"
    fi
    docker compose -f "$ROOT_DIR/docker/docker-compose.production.yml" up -d --build
    ok "Listo. Frontend en ${APP_URL:-http://localhost} / Backend en :4000"
    exit 0
  fi

  say "Arrancando contenedores Docker (dev)…"
  docker compose -f "$ROOT_DIR/docker/docker-compose.yml" up --build
  exit $?
fi

#------------------------------------------------------------------------------
# Modo local
#------------------------------------------------------------------------------
if [ "$MODE" = "lan" ] || [ "$MODE" = "external" ]; then
  IP="$(detect_ip)"
  if [ "$MODE" = "external" ] && [ -z "$EXTERNAL_URL" ]; then
    die "--external requiere una URL (ej: ./start.sh --external https://app.midominio.com)"
  fi
  if [ "$MODE" = "lan" ]; then EXTERNAL_URL="http://$IP:3000"; fi
  say "Direcciones: Frontend=$EXTERNAL_URL  Backend=http://$IP:4000"
  set_env APP_URL "$EXTERNAL_URL"
  set_env BACKEND_URL "http://$IP:4000"
  set_env WEBHOOK_URL "$EXTERNAL_URL/webhooks"
  set_env NEXT_PUBLIC_API_URL "http://$IP:4000"
fi

if $DO_SEED; then
  say "Cargando datos de demostración…"
  (cd "$ROOT_DIR/backend" && npm run prisma:seed) || warn "El seed falló (¿ejecutaste ./install.sh?)."
  ok "Seed completado."
fi

start_background() {
  local name="$1" cmd="$2" log="$3"
  nohup bash -c "$cmd" > "$log" 2>&1 &
  echo $! >> "$PID_FILE"
  ok "$name arrancado (PID $!) → logs/$log"
}

# Configuración según producción/dev
if $PROD; then
  (cd "$ROOT_DIR/backend" && npm run build >/dev/null 2>&1 || true)
  (cd "$ROOT_DIR/frontend" && npm run build >/dev/null 2>&1 || true)
  BACKEND_CMD="cd $ROOT_DIR/backend && NODE_ENV=production npm run start"
  FRONTEND_CMD="cd $ROOT_DIR/frontend && NODE_ENV=production npm run start"
else
  BACKEND_CMD="cd $ROOT_DIR/backend && npm run dev"
  FRONTEND_CMD="cd $ROOT_DIR/frontend && npm run dev"
fi

[ -f "$PID_FILE" ] && rm -f "$PID_FILE"

if [ "$WHO_SERVICE_PROVIDER" = "backend" ] || [ "$WHO_SERVICE_PROVIDER" = "both" ]; then
  start_background "Backend" "$BACKEND_CMD" "backend.log"
fi
if [ "$WHO_SERVICE_PROVIDER" = "frontend" ] || [ "$WHO_SERVICE_PROVIDER" = "both" ]; then
  start_background "Frontend" "$FRONTEND_CMD" "frontend.log"
fi

#------------------------------------------------------------------------------
# Esperar a que los servicios respondan
#------------------------------------------------------------------------------
wait_for() {
  local url="$1" name="$2" retries="${3:-30}"
  local i=0
  printf '\033[1;34m◆\033[0m Esperando a %s…' "$name"
  while [ "$i" -lt "$retries" ]; do
    if curl -sf -o /dev/null --max-time 2 "$url"; then
      printf ' ✓ (%ss)\n' "$((i*2))"
      return 0
    fi
    printf '.'
    sleep 2
    i=$((i+1))
  done
  printf '\n\033[1;33m⚠\033[0m %s no respondió en %ss.\n' "$name" "$((retries*2))"
  warn "Revisa logs/: ${LOG_DIR}/"
  return 1
}

if [ "$WHO_SERVICE_PROVIDER" = "backend" ] || [ "$WHO_SERVICE_PROVIDER" = "both" ]; then
  wait_for "http://localhost:4000/api/health" "Backend" 30 || true
fi
if [ "$WHO_SERVICE_PROVIDER" = "frontend" ] || [ "$WHO_SERVICE_PROVIDER" = "both" ]; then
  wait_for "http://localhost:3000/login" "Frontend" 40 || true
fi

cat <<EOF

════════════════════════════════════════════════════════════════════
  Shopify Manager en marcha
    Frontend:  ${APP_URL:-http://localhost:3000}
    Backend:   http://localhost:4000/api/health

  Logs:  logs/backend.log · logs/frontend.log
  Stop:  ./start.sh --stop
════════════════════════════════════════════════════════════════════
EOF