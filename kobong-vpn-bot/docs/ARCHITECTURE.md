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
│  │ Handlers     │    │ SSH Client    │    │ Pakasir Poller   │  │
│  │ (start, vps, │──▶ │ Pool (async-  │    │ (background      │  │
│  │  ssh, zivpn, │    │  ssh)         │    │  polling loop)   │  │
│  │  payment...) │    └──────┬────────┘    └────────┬─────────┘  │
│  └──────┬───────┘           │                      │            │
│         │                   │                      │            │
│         ▼                   ▼                      ▼            │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ SQLAlchemy (async) ─ SQLite / Postgres                   │  │
│  │ Tables: users, vps, accounts, orders, products           │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
       │                                          │
       │ SSH                                      │ HTTPS GET (poll every 10s)
       ▼                                          ▼
┌──────────────┐                        ┌─────────────────────┐
│ Target VPS 1 │                        │ Pakasir gateway     │
│ (customer)   │                        │ app.pakasir.com     │
│ - xray       │                        │ /api/transaction    │
│ - dropbear   │                        │  detail             │
│ - zivpn      │                        └─────────────────────┘
└──────────────┘
┌──────────────┐
│ Target VPS 2 │
│ ...          │
└──────────────┘
```

**Note**: Bot **outbound-only** ke Pakasir & Telegram. Tidak ada inbound port yang perlu di-expose. No domain / TLS / reverse proxy required.

## Data Model

### `users`
Bot users (bot admins + resellers). NOT the same as VPN account users.

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
| order_ref | string unique | Format: KBG-{tg_user_id}-{hex8} |
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

### Pakasir
- **No webhook = no signature verification needed** — bot pulls data, tidak menerima data
- API key hanya dipakai oleh bot outbound, tidak pernah di-expose

### Admin authorization
- `SUPER_ADMIN_IDS` env → checked at user creation → role assigned once
- Sensitive commands gated with role check middleware (M6)

## Concurrency

- Bot handlers async, run in shared event loop
- SSH operations via `asyncssh` connection pool (configurable `SSH_POOL_SIZE`)
- Payment polling: 1 background task per pending order (auto-resume on restart)
- Database sessions short-lived per handler (context manager)

## Deployment

- **Docker Compose** (recommended) — no ports exposed, outbound-only
- **Systemd** fallback tersedia
- `data/` volume mounted untuk SQLite + logs
- **Tidak butuh** reverse proxy / TLS cert / domain
