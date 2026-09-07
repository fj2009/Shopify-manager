# Shopify Manager

Aplicación web de **gestión y analítica de negocio para tiendas Shopify** (multi-almacén, multi-moneda, impuestos UE, inventario, costes y beneficios).

- **Backend**: Node.js + Express + TypeScript + Prisma + PostgreSQL + Redis (`backend/`)
- **Frontend**: Next.js 14 (App Router) + React + Tailwind, modo oscuro (`frontend/`)
- **Infra**: Docker Compose, scripts `install.sh` / `start.sh`, backup/restore

---

## Funcionalidades

- **Integración Shopify** oficial vía OAuth (tokens encriptados en repositorio), scopes mínimos, webhooks firmados por HMAC e idempotentes.
- **Sincronización** completa e incremental de productos, variantes, clientes, pedidos e inventario con control de rate-limit de la API de Shopify.
- **Inventario multi-ubicación**: niveles, movimientos, alertas (stock bajo/sin stock), ajustes con auditoría.
- **Costes y beneficios**: coste histórico por variante, COGS con valor en la fecha de venta, beneficio por pedido/línea/producto.
- **Finanzas**: P&L (bruto/operativo/neto), ventas por día, top productos/variantes, gastos por categoría.
- **Impuestos**: registros de IVA por pedido, base imponible/cuota por tipo, resumen a liquidar.
- **Informes y exportación CSV** (ventas, beneficio, inventario, gastos, impuestos, clientes).
- **Seguridad**: argon2id para contraseñas, JWT + sesiones revocables, RBAC (ADMIN/MANAGER/EMPLOYEE/VIEWER), rate-limiting, auditoría completa, helmet/CORS.
- **Multi-usuario y multi-tienda** por organización, con configuración (moneda, país, zona horaria, impuestos).
- **Busqueda global** (pedidos, productos, variantes, clientes) y dashboard con métricas.

## Stack

| Componente | Tecnología |
|---|---|
| Backend | Express 4, TypeScript, Prisma 5, BullMQ, zod, winston |
| Frontend | Next.js 14, React 18, Tailwind 3, lucide-react, recharts |
| Base de datos | PostgreSQL 16 |
| Caché/cola | Redis 7 |
| Contenedores | Docker / Docker Compose |

## Requisitos

- Node.js ≥ 18 (recomendado 20 LTS), npm ≥ 9
- PostgreSQL ≥ 14 y Redis ≥ 6 (o Docker)
- Credenciales de una **Shopify App privada/custom** → `SHOPIFY_API_KEY`, `SHOPIFY_API_SECRET`

## Instalación rápida

```bash
cp .env.example .env        # y rellena SHOPIFY_API_KEY / SHOPIFY_API_SECRET
./install.sh                # instala dependencias, crea BD y aplica migraciones
./install.sh --seed         # opcional: datos de demostración
./start.sh                  # modo local (desarrollo)
./start.sh --lan            # accesible desde la red local
./start.sh --docker         # o bien contenedores Docker
```

Usuario de demostración (si se usó `--seed`): `admin@example.com` / `Admin123!`

> **Seguridad**: cambia la contraseña por defecto nada más entrar. Puedes revocar el acceso con `npm run prisma:seed` (no recomendado en producción) o borrando el usuario en `Usuarios`.

## Entorno (`.env`)

| Variable | Descripción |
|---|---|
| `DATABASE_URL` | Conexión PostgreSQL |
| `REDIS_URL` | Conexión Redis |
| `SHOPIFY_API_KEY` / `SHOPIFY_API_SECRET` | Credenciales de la app de Shopify |
| `SHOPIFY_SCOPES` | Scopes solicitados en OAuth |
| `SHOPIFY_API_VERSION` | Versión de la Admin API (p. ej. `2024-01`) |
| `ENCRYPTION_KEY` | Clave AES-256-GCM para encriptar tokens (32 bytes hex) |
| `SESSION_SECRET` | Secreto para firmar JWT (≥ 32 caracteres) |
| `APP_URL` / `BACKEND_URL` / `WEBHOOK_URL` | URLs pública/privada de la app y del webhook |
| `NODE_ENV` | `development` / `production` / `test` |

Genera secretos con: `openssl rand -hex 16` (encryption) y `openssl rand -hex 32` (session).

## Comandos

Todos los de backend se ejecutan desde `backend/`; los de frontend desde `frontend/`.

```bash
# Backend
npm run dev                # servidor con hot reload (puerto 4000)
npm run build              # tsc → dist/
npm run start              # ejecuta la build
npm test                   # tests unitarios (node:test) + smoke
npm run typecheck          # tsc --noEmit
npm run prisma:generate    # regenera el cliente Prisma
npm run prisma:migrate     # migraciones en desarrollo
npm run prisma:deploy      # migraciones en producción
npm run prisma:seed        # datos de demostración

# Frontend
npm run dev                # next dev (puerto 3000)
npm run build              # next build
npm run start              # next start (producción)
```

## Despliegue

- **Instalación automática** → [`install.sh`](install.sh)
- **Arranque (local/LAN/Docker)** → [`start.sh`](start.sh)
- **Contenedores de producción** → `./start.sh --docker --prod` o `docker compose -f docker/docker-compose.production.yml up -d --build`
- **Manual detallado** → [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)

## Más documentación

- [Arquitectura](docs/ARCHITECTURE.md)
- [Base de datos](docs/DATABASE.md)
- [Integración Shopify](docs/SHOPIFY.md)
- [Seguridad](docs/SECURITY.md)
- [Copias de seguridad](docs/BACKUPS.md)
- [Solución de problemas](docs/TROUBLESHOOTING.md)

## Licencia

Uso interno / privado. Sin licenciamiento público por defecto.