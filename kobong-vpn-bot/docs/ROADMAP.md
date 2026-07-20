# Roadmap — KOBONG VPN BOT

## ✅ M1 — Scaffold & Fondasi (done)

- Project structure, requirements, systemd installer (no Docker)
- Pydantic-based config with `.env` validation
- Async SQLAlchemy ORM: `User`, `VPS`, `Account`, `Order`, `Product`
- Fernet-based encryption for VPS credentials
- KOBONG banner + full menu keyboards (14 sections)
- `/start` with role-aware main menu
- Pakasir Python client (polling-based, no webhook)
- Background `PaymentPoller` (crash-safe resume)
- Fresh install scripts (no WendyVpn refs)

## ✅ M2 — VPS Registration & Install Automation (done)

- ConversationHandler wizard `➕ Tambah VPS` (label → host → port → user → creds → verify)
- `KobongSSH` async wrapper + `SSHConnectionPool` (semaphore-limited)
- `verify_credentials()` runs full login test before saving to DB
- Credentials encrypted with Fernet before persist
- Auto-delete user's password message from chat history
- `InstallOrchestrator`: upload scripts → run with live stdout tail →
  parse stage markers → **live progress bar via edit-message**
- 30-min hard timeout, error surfacing with log tail
- VPS status transitions: `pending → installing → active/error`
- Auto-populate `installed_protocols` after success

## ✅ M3 — SSH Account CRUD (done)

- `services/ssh_accounts.py` — remote `useradd` + `chpasswd` + `chage -E`
- kobong-ssh group marker for safe tracking
- Restricted shell (`/bin/false`) — tunneling only, no shell access
- Balance deduction with automatic refund on remote failure
- Config text output ready-to-paste into SSH tunnel apps
- Flows: **Create / List / Delete / Renew** — all inline
- Duration-proportional pricing (default: Rp 5000 / 30 days)

## ✅ M4 — ZIVPN Account CRUD (done)

- Password-based auth via `/etc/kobong/zivpn/config.json`
- Idempotent read → modify → write JSON
- Auto-restart `kobong-zivpn` service on config change
- Flows: **Create / List / Delete / Restart Service**
- Rollback on DB-side conflict (removes password if account insert fails)
- Config text with host, port, obfs, DNAT range info

---

## 🚧 M5 — Xray Protocols CRUD (next)

Untuk VMess/VLESS/Trojan/Shadowsocks, butuh manipulasi
`/etc/xray/config.json` yang lebih kompleks:

- [ ] `services/xray_accounts.py` — safe JSON manipulation via `jq` di remote
- [ ] Generate UUID untuk VMess/VLESS
- [ ] Auto-restart xray service after config change
- [ ] Generate ready-to-paste `vmess://` / `vless://` / `trojan://` / `ss://` URLs
- [ ] QR code image untuk scan langsung di client apps
- [ ] Flows: Create / List / Delete / Renew per protokol

---

## 🚧 M6 — Extras

- [ ] Trial account (durasi pendek, quota terbatas, tanpa potong saldo)
- [ ] Backup config VPS ke Google Drive via rclone
- [ ] Restore dari backup
- [ ] Stats real-time (bandwidth via vnstat, RAM/CPU) via SSH probes
- [ ] Autoreboot scheduler (systemd timer di target VPS)
- [ ] Settings: ganti domain, banner text, harga produk per-user

---

## 🚧 M7 — Admin Panel + Reporting

- [ ] `/admin` command untuk super admin only
- [ ] Manage users: promote/demote, ban, adjust balance
- [ ] Broadcast pesan ke semua user
- [ ] Laporan penjualan (harian/mingguan/bulanan)
- [ ] Export CSV
- [ ] Set harga per-produk (SSH/VMess/VLESS/Trojan/Shadow/ZIVPN × durasi)
- [ ] Multi-VPS picker (kalau reseller punya banyak VPS aktif)
- [ ] Expiry notification: bot auto-DM user H-1 sebelum akun expired

---

## 🚧 M8 — Payment Polish

- [ ] Custom nominal input (bukan cuma preset)
- [ ] Faktur PDF ke chat setelah pembayaran
- [ ] Refund flow (approve manual by admin)
- [ ] Voucher/promo code
- [ ] Batching untuk laporan revenue per gateway

---

**Rilis strategi:** M1-M4 sudah production-ready untuk testing. M5+ ditambah bertahap setelah user validasi flow existing.
