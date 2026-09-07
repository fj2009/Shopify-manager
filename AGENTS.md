# AGENTS.md

## Project Structure

Two independent npm packages (not a monorepo — no shared tooling, separate `node_modules`):

- **`backend/`** — Express + TypeScript API. Entry: `src/index.ts`. Layered: routes → controllers → services → providers.
- **`frontend/`** — Next.js 14 + React + Tailwind. All pages fully built and responsive. Dark mode supported.
- **`docker/`** — Dockerfiles (multi-stage, non-root, production-optimized) and Compose files.
- **`scripts/`** — `backup.sh`, `restore.sh` (PostgreSQL via pg_dump/pg_restore).
- **Root**: `install.sh`, `start.sh`, `.env.example`, `.env`, `.gitignore`, `.dockerignore`.

## Commands

All backend commands run from `backend/`. All frontend commands run from `frontend/`.

```bash
# Backend
cd backend && npm run dev            # ts-node-dev hot-reload server (port 4000)
cd backend && npm run build          # tsc → dist/
cd backend && npm run start          # node dist/index.js
cd backend && npm test               # unit tests + API smoke (node:test)
cd backend && npm run typecheck      # tsc --noEmit
cd backend && npm run prisma:generate  # regenerate Prisma client after schema changes
cd backend && npm run prisma:migrate   # run migrations (development)
cd backend && npm run prisma:deploy    # run migrations (production)
cd backend && npm run prisma:seed      # load demo data (admin@example.com / Admin123!)

# Frontend
cd frontend && npm run dev           # next dev (port 3000)
cd frontend && npm run build         # next build (standalone)
cd frontend && npm run start         # next start (production)
cd frontend && npm run lint          # next lint

# Full stack local
./install.sh                 # install deps, create DB, run migrations
./install.sh --seed          # install + load demo data
./start.sh                   # local dev mode (backend + frontend in background)
./start.sh --lan             # accessible from local network
./start.sh --docker          # docker-compose dev
./start.sh --docker --prod   # docker-compose production
./start.sh --stop            # stop background processes

# Docker
docker compose -f docker/docker-compose.yml up --build
docker compose -f docker/docker-compose.production.yml up -d --build

# Backup / Restore
./scripts/backup.sh
./scripts/backup.sh --keep 30 --include-env
./scripts/restore.sh backups/shopify_manager_YYYYMMDD_HHMMSS.dump
```

## Environment

Copy `.env.example` to `.env` at the repo root. Required vars: `DATABASE_URL`, `REDIS_URL`, `SHOPIFY_API_KEY`, `SHOPIFY_API_SECRET`, `ENCRYPTION_KEY`, `SESSION_SECRET`.

Generate real secrets: `openssl rand -hex 16` (ENCRYPTION_KEY), `openssl rand -hex 32` (SESSION_SECRET).

The backend reads env via `src/config/env.ts` using dotenv (loads root `.env` via symlink).

## Database

Prisma schema: `backend/prisma/schema.prisma`. After any schema change: `npm run prisma:generate && npm run prisma:migrate` from `backend/`.

Migrations are in `backend/prisma/migrations/`. Never edit them after apply.

## Key Conventions

- Backend uses **argon2** for passwords, **JWT** for auth, **zod** for validation, **winston** for logging.
- Shopify access tokens are encrypted at rest with **AES-256-GCM** (see `ENCRYPTION_KEY`).
- All frontend UI text is in **Spanish**.
- `AGENTS.md` is the authoritative instruction source for this project.