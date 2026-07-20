# Roadmap — KOBONG VPN BOT

## M1 — Scaffold & Fondasi ✅ (delivered)

**What's in:**

- ✅ Project structure, requirements, Dockerfile, docker-compose
- ✅ Pydantic-based config with `.env` validation
- ✅ Async SQLAlchemy ORM: `User`, `VPS`, `Account`, `Order`, `Product`
- ✅ Fernet-based encryption module for VPS credentials
- ✅ Full menu keyboard skeleton (14 sections matching VPS terminal menu)
- ✅ `/start` command with KOBONG banner + role-aware main menu
- ✅ Pakasir Python client (create + detail — polling-based, no webhook)
- ✅ Background PaymentPoller (10s interval, 10-min window, crash-safe resume)
- ✅ Fresh install scripts (`kobong-install.sh`, `install_zivpn.sh`) — NO WendyVpn references
- ✅ ZIVPN UDP installer with DNAT range 6000-19999
- ✅ Zero-config deployment (no domain / TLS / reverse proxy required)

**Test criteria before M2:**
- [ ] `docker compose up -d` starts without error
- [ ] `/start` shows KOBONG banner and inline menu
- [ ] Every menu button responds (even if stub says "coming in M2")
- [ ] `💰 Top Up Saldo → Rp 10.000 → QRIS` creates a real Pakasir transaction
- [ ] Bot logs `Poll KBG-xxx [1/60]: status=pending` every 10 seconds
- [ ] Paying (or simulating) the transaction on Pakasir dashboard credits balance auto within 10-20s

---

## M2 — VPS Registration & Install Automation

- [ ] Conversation handler untuk wizard `➕ Tambah VPS`
- [ ] `asyncssh` pool + connection retry
- [ ] Verifikasi SSH login otomatis setelah input kredensial
- [ ] Upload `kobong-install.sh` ke VPS + jalankan pakai `screen`/`tmux`
- [ ] Live progress streaming via SSH stdout tail → edit-message di Telegram
- [ ] Save `installed_protocols` ke DB setelah selesai
- [ ] `/status <vps>` command untuk cek services di VPS

---

## M3 — Xray Account CRUD

- [ ] Refactor bash scripts jadi JSON output
- [ ] `createvmess`, `createvless`, `createtrojan`, `createshadowsocks` remote via SSH
- [ ] Parse output → simpan ke `Account` table
- [ ] Kirim config text + QR code ke user
- [ ] `List` akun dengan pagination
- [ ] `Renew` (extend expiry, potong saldo)
- [ ] `Delete` (soft-delete di DB, hapus di server)
- [ ] `Lock/Unlock` (disable tanpa hapus)
- [ ] `Cek Login` (jumlah IP aktif)

---

## M4 — ZIVPN CRUD + Service Control

- [ ] `createzivpn`: add password ke config.json, restart service
- [ ] `delzivpn`: remove password
- [ ] `renewzivpn`: update expiry di DB (password sama)
- [ ] `restart`, `status` service dari Telegram
- [ ] Ganti port ZIVPN (auto-update DNAT rules)
- [ ] Ganti obfs / rotate passwords

---

## M5 — Extras

- [ ] Trial akun (durasi pendek, quota terbatas)
- [ ] Backup config ke Google Drive via rclone
- [ ] Restore dari backup
- [ ] Stats real-time (bandwidth via vnstat, RAM/CPU)
- [ ] Autoreboot scheduler
- [ ] Settings: ganti domain, banner text, harga produk

---

## M6 — Admin Panel

- [ ] `/admin` command untuk super admin
- [ ] Manage users: promote/demote, ban, adjust balance
- [ ] Broadcast pesan ke semua user
- [ ] Set harga per produk (SSH/VMess/VLESS/Trojan/Shadow/ZIVPN × durasi)
- [ ] Laporan penjualan (harian/mingguan/bulanan)
- [ ] Export CSV

---

## M7 — Payment Polish

- [x] Poller auto-credit (M1)
- [ ] Custom amount input (bukan hanya preset)
- [ ] Faktur/receipt PDF ke chat setelah pembayaran
- [ ] Refund flow (manual approve by admin)
- [ ] Retry pending payments jika bot crash panjang
- [ ] Alert user H-1 sebelum akun expired untuk renew otomatis
