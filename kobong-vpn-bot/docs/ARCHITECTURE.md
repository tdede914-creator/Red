# Arsitektur KOBONG VPN BOT

## Overview

```
                      ┌────────────────────────┐
                      │  Telegram BotAPI       │
                      └──────────┬─────────────┘
                                 │ long polling
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                    KOBONG BOT (VPS terpisah)                     │
│                                                                  │
│  ┌──────────────┐    ┌───────────────┐    ┌──────────────────┐  │
│  │ Handlers     │    │ SSH Client    │    │ Pakasir Client   │  │
│  │ (start, vps, │──▶ │ Pool (async-  │    │ (create/detail/  │  │
│  │  ssh, zivpn, │    │  ssh)         │    │  webhook)        │  │
│  │  payment...) │    └──────┬────────┘    └────────┬─────────┘  │
│  └──────┬───────┘           │                      │            │
│         │                   │                      │            │
│         ▼                   ▼                      ▼            │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ SQLAlchemy (async) ─ SQLite / Postgres                   │  │
│  │ Tables: users, vps, accounts, orders, products           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ aiohttp webhook server  :8080                            │  │
│  │  GET  /health                                            │  │
│  │  POST /webhook/pakasir  (payment callbacks)              │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
       │                                          ▲
       │ SSH                                      │ HTTPS POST
       ▼                                          │
┌──────────────┐                        ┌─────────┴──────────┐
│ Target VPS 1 │                        │ Pakasir gateway    │
│ (customer)   │                        │  app.pakasir.com   │
│ - xray       │                        └────────────────────┘
│ - dropbear   │
│ - zivpn      │
│ - kobong-install.sh                                        
└──────────────┘
┌──────────────┐
│ Target VPS 2 │
│ ...          │
└──────────────┘
```

## Data Model

### `users`
Bot users (bot owners + resellers). NOT the same as VPN account users.

| Column | Type | Notes |
|--------|------|-------|
| id | int PK | |
| telegram_id | bigint unique | |
| role | enum | super_admin / reseller / client / banned |
| balance | int | Rupiah |

### `vps`
Registered target VPS servers.

| Column | Type | Notes |
|--------|------|-------|
| owner_id | FK users | |
| label | string | e.g. "SG1" |
| host, port, ssh_user | | |
| ssh_password_enc, ssh_key_enc | text | Fernet encrypted |
| status | enum | pending/installing/active/error/disabled |
| installed_protocols | csv string | e.g. "xray,ssh,zivpn" |

### `accounts`
VPN accounts created on a VPS.

| Column | Type | Notes |
|--------|------|-------|
| vps_id | FK vps | |
| protocol | enum | ssh, vmess, vless, trojan, shadowsocks, zivpn, openvpn |
| username, password, uuid | | Protocol-specific |
| ip_limit, quota_gb | | |
| expires_at | datetime | |
| config_json | text | Full config for client |

### `orders`
Top-up transactions via Pakasir.

| Column | Type | Notes |
|--------|------|-------|
| order_ref | string unique | Format: KBG-{user_id}-{hex8} |
| user_id | FK users | |
| amount | int | Rupiah |
| payment_method | string | qris, bri_va, etc |
| status | enum | pending/completed/canceled/expired/failed |

### `products`
Sellable plans (protocol × duration → price).

## Security

### VPS credentials
- Stored as `Fernet(FERNET_KEY).encrypt(password_or_key)` in `ssh_password_enc` / `ssh_key_enc`
- FERNET_KEY MUST be stable across bot restarts (else old data unreadable)
- Rotation supported via `bot.crypto.rotate(old_key, new_key, ciphertext)`

### Pakasir webhook
- Verified with HMAC-SHA256 of raw body using `PAKASIR_WEBHOOK_SECRET`
- Header: `X-Pakasir-Signature` (may need to update once Pakasir publishes their scheme)
- Idempotent: re-processing a completed order is a no-op

### Admin authorization
- `SUPER_ADMIN_IDS` env → checked at user creation → role assigned once
- Sensitive commands gated with role check middleware (M6)

## Concurrency

- Bot handlers are async, run in shared event loop
- SSH operations use `asyncssh` connection pool (configurable `SSH_POOL_SIZE`)
- Database sessions are short-lived per handler (context manager)
- Long-running installs run as detached tasks with progress via edit-message

## Deployment

- Docker Compose (recommended)
- Reverse proxy (Caddy/Nginx) for TLS termination on webhook
- `data/` volume mounted for SQLite + logs
- Systemd fallback if not using Docker
