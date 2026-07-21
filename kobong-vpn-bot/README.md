# 🌙 KOBONG VPN BOT

> Multi-tenant Telegram bot untuk install & kelola VPN tunneling di VPS.
> Support **SSH & ZIVPN full-CRUD** + auto-install stack (VMess/VLESS/Trojan/Shadowsocks/OpenVPN/SlowDNS).
> Semua diakses lewat menu inline Telegram, tanpa perlu SSH manual.

```
╔═══════════════════════════════════════════════════════════╗
║   ██╗  ██╗ ██████╗ ██████╗  ██████╗ ███╗   ██╗ ██████╗    ║
║   ██║ ██╔╝██╔═══██╗██╔══██╗██╔═══██╗████╗  ██║██╔════╝    ║
║   █████╔╝ ██║   ██║██████╔╝██║   ██║██╔██╗ ██║██║  ███╗   ║
║   ██╔═██╗ ██║   ██║██╔══██╗██║   ██║██║╚██╗██║██║   ██║   ║
║   ██║  ██╗╚██████╔╝██████╔╝╚██████╔╝██║ ╚████║╚██████╔╝   ║
║   ╚═╝  ╚═╝ ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝    ║
║                     V P N   B O T                         ║
╚═══════════════════════════════════════════════════════════╝
```

---

## ⚡ Quickstart (One Command)

Di VPS bot kamu (Ubuntu 22.04 / Debian 12), jalanin sebagai root:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tdede914-creator/Red/feat/kobong-vpn-bot-m1/kobong-vpn-bot/install-bot.sh)
```

Installer interaktif akan nanya:
1. Bot token dari @BotFather
2. Bot username
3. Telegram user ID kamu (dari @userinfobot)
4. Pakasir slug + API key (opsional — bisa di-skip)

Setelah selesai, chat bot kamu di Telegram → `/start` → siap pakai.

Detail step-by-step: **[docs/SETUP.md](docs/SETUP.md)**.

---

## ✨ Fitur

### Sudah bisa dites sekarang
- **➕ Wizard tambah VPS** — daftarkan VPS target lewat chat (label → host → port → user → password/key), auto-verify SSH login
- **🚀 Install remote** — bot upload `kobong-install.sh` via SSH & jalankan dengan **progress bar live** di Telegram
- **🔐 SSH accounts** — Create/List/Delete/Renew dengan auto-format config text
- **🚀 ZIVPN accounts** — Create/List/Delete + restart service, password langsung di-inject ke `/etc/kobong/zivpn/config.json`
- **💰 Payment Pakasir polling** — QRIS/VA, auto-cek tiap 10s, auto-credit saldo
- **💳 Balance-based purchasing** — potong saldo saat create akun, auto-refund kalau gagal
- **🔒 Kredensial VPS di-encrypt** (Fernet AES-128) sebelum masuk DB
- **👥 Multi-tenant** — user lain bisa daftar sebagai reseller, kelola VPS sendiri

### Coming next (butuh manipulasi Xray config JSON)
- 📦 VMess/VLESS/Trojan/Shadowsocks CRUD
- 🆓 Trial account
- 📊 Stats bandwidth/RAM real-time
- 💾 Backup ke GDrive
- 👑 Admin panel

---

## 🗺️ Roadmap

| Milestone | Status |
|-----------|--------|
| **M1** Scaffold + Pakasir polling | ✅ Done |
| **M2** VPS wizard + install trigger + live progress | ✅ Done |
| **M3** SSH account CRUD | ✅ Done |
| **M4** ZIVPN account CRUD | ✅ Done |
| **M5** Xray protocols (VMess/VLESS/Trojan/Shadow) CRUD | ⏳ Next |
| **M6** Trial + Backup + Stats | ⏳ |
| **M7** Admin panel + laporan | ⏳ |

---

## 🖥️ VPS Requirements

### Bot VPS (server untuk KOBONG BOT sendiri)
- Ubuntu 22.04 / Debian 12
- 1 vCPU, 512 MB RAM, 5 GB disk
- Outbound internet ke `api.telegram.org` & `app.pakasir.com`
- **Tidak butuh** inbound port terbuka, domain, atau SSL cert

### Target VPS (yang mau di-install VPN stack)
- Ubuntu 20.04+ / Debian 10+
- Arsitektur x86_64
- Root SSH access
- 512+ MB RAM (1 GB recommended)
- **Tidak boleh OpenVZ** (butuh systemd + iptables NAT)

---

## 💰 Cara Kerja Payment (Pakasir Polling)

```
1. User: Top Up Saldo → Rp 10.000 → QRIS
2. Bot call Pakasir.createPayment() → dapat QR + payment URL
3. Bot kirim link/QR + start background poller (cek tiap 10s)
4. User bayar via aplikasi bank/e-wallet
5. Poller detect status="completed" → auto-credit saldo + notif Telegram
```

**Kenapa polling bukan webhook?** Tidak butuh:
- Domain publik ~~~~
- TLS certificate ~~~~
- Reverse proxy ~~~~
- Konfigurasi webhook di dashboard ~~~~

Bot cukup punya akses outbound internet. Detail: **[docs/PAYMENT.md](docs/PAYMENT.md)**.

---

## 📱 Alur Pemakaian

### Bagi kamu (super admin)

1. `/start` → cek badge **👑 SUPER ADMIN**
2. **🖥 VPS → ➕ Tambah VPS Baru** → wizard 6-step
3. Setelah VPS ke-registered → klik **🚀 Install Stack**
4. Tunggu 5-10 menit (bot kasih progress bar live)
5. Setelah selesai:
   - **🔐 SSH → Buat Akun** untuk client kamu
   - **🚀 ZIVPN → Buat Akun** untuk yang butuh UDP tunnel

### Bagi reseller kamu

1. `/start` → auto-daftar sebagai `RESELLER`
2. **💰 Top Up Saldo** → pilih nominal → bayar QRIS
3. Bisa daftarin VPS sendiri, atau langsung create akun di VPS kamu
4. Saldo terpotong sesuai harga (`DEFAULT_PRICE_SSH`, `DEFAULT_PRICE_ZIVPN` di .env)

---

## 🎛️ Perintah Berguna Setelah Install

```bash
# Cek status bot
systemctl status kobong-vpn-bot

# Lihat log realtime
tail -f /opt/kobong-vpn-bot/logs/bot.log
# atau
journalctl -u kobong-vpn-bot -f

# Restart bot
systemctl restart kobong-vpn-bot

# Update dari GitHub
cd /opt/kobong-vpn-bot && sudo -u kobong git pull && systemctl restart kobong-vpn-bot

# Backup data + .env
sudo tar czf ~/kobong-backup-$(date +%Y%m%d).tar.gz -C /opt/kobong-vpn-bot data .env

# Uninstall bot (opsi backup data)
bash /opt/kobong-vpn-bot/uninstall-bot.sh
```

---

## 🏗️ Struktur Project

```
kobong-vpn-bot/
├── install-bot.sh              # One-shot installer (systemd)
├── uninstall-bot.sh
│
├── bot/
│   ├── __main__.py             # Entry point
│   ├── config.py               # Env-based Pydantic settings
│   ├── db.py + models.py       # Async SQLAlchemy ORM
│   ├── crypto.py               # Fernet encryption for VPS creds
│   ├── balance.py              # Deduct/refund helpers
│   ├── ssh_client.py           # asyncssh wrapper + connection pool
│   ├── install_orchestrator.py # Runs kobong-install.sh with live progress
│   ├── pakasir.py              # Payment gateway client (polling)
│   ├── payment_poller.py       # Background task per pending order
│   ├── banner.py + keyboards.py
│   ├── services/
│   │   ├── ssh_accounts.py     # SSH CRUD business logic
│   │   └── zivpn_accounts.py   # ZIVPN CRUD business logic
│   └── handlers/
│       ├── start.py            # /start + main menu
│       ├── vps.py              # VPS wizard + install trigger
│       ├── ssh_account.py      # SSH Telegram flows
│       ├── zivpn_account.py    # ZIVPN Telegram flows
│       ├── payment.py          # Top-up flow
│       ├── account_common.py   # Shared VPS-picker + no-VPS error
│       └── protocol_stub.py    # Fallback for not-yet-implemented protocols
├── scripts/
│   ├── kobong-install.sh       # Runs on target VPS (base + xray + SSH + ZIVPN)
│   ├── install_zivpn.sh        # ZIVPN UDP installer
│   └── uninstall.sh
└── docs/
    ├── SETUP.md
    ├── PAYMENT.md
    ├── ARCHITECTURE.md
    └── ROADMAP.md
```

---

## 🔐 Kredensial Bocor di Parent Repo

Waktu audit `Red` sebelumnya saya nemu 3 secret ter-hardcode publik:

1. Gmail: `oceantestdigital@gmail.com` / password `jokerman77`
2. Bot token: `7117869623:AAHBmg…`
3. Bot token: `7660217485:AAHyPV…`

**Wajib revoke SEKARANG:**
- Ganti password Gmail di [myaccount.google.com](https://myaccount.google.com/security)
- Revoke bot tokens di @BotFather → `/revoke`

Bot baru ini semua kredensial via `.env` (di-generate installer, permissions 600).

---

## 📜 Lisensi

MIT — bebas dipakai personal maupun komersial.

**Made with 🌙 by KOBONG**
