#!/usr/bin/env bash
#===============================================================================
# install.sh — Instala y prepara Shopify Manager (backend + frontend + DB).
#
# Uso:
#   ./install.sh                  # instalación estándar local
#   ./install.sh --seed           # instala y carga datos de demostración
#   ./install.sh --docker         # prepara el entorno Docker (ops)
#   ./install.sh --skip-prereqs   # no comprueba dependencias del sistema
#===============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
FRONTEND_DIR="$ROOT_DIR/frontend"

DO_SEED=false
DOCKER_MODE=false
CHECK_PREREQS=true

for arg in "$@"; do
  case "$arg" in
    --seed) DO_SEED=true ;;
    --docker) DOCKER_MODE=true ;;
    --skip-prereqs) CHECK_PREREQS=false ;;
    --help|-h)
      sed -n '2,14p' "$0"
      exit 0
      ;;
    *) echo "⚠ Opción desconocida: $arg" ;;
  esac
done

say()  { printf '\033[1;34m◆\033[0m %s\n' "$1"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m⚠\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31m✗\033[0m %s\n' "$1" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

#------------------------------------------------------------------------------
# 1. Prerequisitos
#------------------------------------------------------------------------------
if $CHECK_PREREQS; then
  say "Comprobando prerequisitos…"
  have node   || die "Se necesita Node.js >= 18. Instálalo y vuelve a ejecutar."
  have npm    || die "Se necesita npm."
  NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
  [ "$NODE_MAJOR" -ge 18 ] || die "Node.js >= 18 requerido (tienes $(node -v))."
  ok "Node.js $(node -v) / npm $(npm -v)"

  if $DOCKER_MODE; then
    have docker || die "Se necesita Docker Engine. Instálalo o usa el modo local (sin --docker)."
    [ "$(docker info >/dev/null 2>&1; echo $?)" = "0" ] || die "El demonio de Docker no está accesible."
    have docker || true
    docker compose version >/dev/null 2>&1 || die "Se necesita docker compose plugin v2."
    ok "Docker $(docker --version) / compose $(docker compose version --short)"
  fi
fi

#------------------------------------------------------------------------------
# 2. Configuración (.env)
#------------------------------------------------------------------------------
ENV_FILE="$ROOT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  say "Creando .env desde .env.example…"
  cp "$ROOT_DIR/.env.example" "$ENV_FILE"

  ENC="$(openssl rand -hex 16 2>/dev/null || head -c32 </dev/urandom | xxd -p -c1000)"
  SES="$(openssl rand -hex 32 2>/dev/null || head -c64 </dev/urandom | xxd -p -c1000)"
  if [ -n "$ENC" ] && [ -n "$SES" ]; then
    sed -i.bak "s/^ENCRYPTION_KEY=.*/ENCRYPTION_KEY=$ENC/" "$ENV_FILE"
    sed -i.bak "s/^SESSION_SECRET=.*/SESSION_SECRET=$SES/" "$ENV_FILE"
    rm -f "$ENV_FILE.bak"
  fi
  ok "Archivo .env creado. Edítalo para añadir SHOPIFY_API_KEY y SHOPIFY_API_SECRET."
else
  say ".env ya existe — se conserva."
fi

if grep -q '^SHOPIFY_API_KEY=your_api_key' "$ENV_FILE"; then
  warn "SHOPIFY_API_KEY sin configurar (valor 'your_api_key'). La integración Shopify no funcionará hasta rellenarlo."
fi

#------------------------------------------------------------------------------
# 3. Instalar dependencias
#------------------------------------------------------------------------------
if $DOCKER_MODE; then
  say "Modo Docker: las dependencias se instalan dentro de las imágenes."
else
  say "Instalando dependencias del backend…"
  (cd "$BACKEND_DIR" && npm install) || die "Falló npm install (backend)."
  ok "Backend listo."

  say "Instalando dependencias del frontend…"
  (cd "$FRONTEND_DIR" && npm install) || die "Falló npm install (frontend)."
  ok "Frontend listo."
fi

#------------------------------------------------------------------------------
# 4. Base de datos (solo modo local)
#------------------------------------------------------------------------------
DB_URL="${DATABASE_URL:-}"
if [ -z "$DB_URL" ] && [ -f "$ENV_FILE" ]; then
  DB_URL="$(grep '^DATABASE_URL=' "$ENV_FILE" | cut -d= -f2- | tr -d '"')"
fi

if $DOCKER_MODE; then
  say "Modo Docker: la base de datos se crea automáticamente al levantar compose."
else
  say "Preparando base de datos…"
  if have pg_isready && pg_isready -q 2>/dev/null; then
    PG_USER="$(grep '^POSTGRES_USER=' "$ENV_FILE" | cut -d= -f2- || echo postgres)"
    PG_DB="$(grep '^POSTGRES_DB=' "$ENV_FILE" | cut -d= -f2- || echo shopify_manager)"
    PG_PASS="$(grep '^POSTGRES_PASSWORD=' "$ENV_FILE" | cut -d= -f2- || echo postgres)"
    export PGPASSWORD="${PG_PASS:-postgres}"

    if ! psql -U "$PG_USER" -h localhost -lqt | cut -d '|' -f1 | grep -qw "$PG_DB"; then
      createdb -U "$PG_USER" -h localhost "$PG_DB" 2>/dev/null \
        || psql -U "$PG_USER" -h localhost -c "CREATE DATABASE $PG_DB;" >/dev/null \
        || warn "No se pudo crear la BD '$PG_DB'. Créala manualmente y ejecuta 'npm run prisma:migrate' en backend/."
      ok "Base de datos '$PG_DB' creada."
    else
      ok "Base de datos '$PG_DB' ya existe."
    fi
    unset PGPASSWORD
  else
    warn "PostgreSQL local no está respondiendo. Asegúrate de que corre y luego ejecuta:"
    warn "  cd backend/ && npm run prisma:migrate"
  fi

  say "Generando cliente Prisma y aplicando migraciones…"
  (cd "$BACKEND_DIR" && npx prisma generate && npx prisma migrate deploy) || \
    warn "Las migraciones fallaron. Revisa la conexión a PostgreSQL y vuelve a ejecutarlas."
  ok "Esquema de base de datos al día."
fi

#------------------------------------------------------------------------------
# 5. Datos de demostración (opcional)
#------------------------------------------------------------------------------
if $DO_SEED; then
  say "Cargando datos de demostración…"
  (cd "$BACKEND_DIR" && npm run prisma:seed) || die "El seed falló. Revisa backend/prisma/seed.ts."
  ok "Datos de demostración cargados."
fi

#------------------------------------------------------------------------------
# 6. Resumen final
#------------------------------------------------------------------------------
cat <<EOF

════════════════════════════════════════════════════════════════════
  Instalación completada ✅

  Usuario administrador por defecto (si se ejecutó con --seed):
    email:  admin@example.com
    pass:   Admin123!

  Siguientes pasos:
    1. ./start.sh                 → modo local (desarrollo)
       ./start.sh --lan          → accesible desde la red local
       ./start.sh --docker       → contenedores Docker
       ./start.sh --docker --prod → contenedores de producción
    2. O, en modo Docker: docker compose -f docker/docker-compose.yml up --build
════════════════════════════════════════════════════════════════════
EOF