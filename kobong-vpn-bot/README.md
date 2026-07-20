# 🌙 KOBONG VPN BOT

> Multi-tenant Telegram bot untuk install & kelola VPN tunneling di VPS.
> Support **SSH, VMess, VLESS, Trojan, Shadowsocks, ZIVPN, OpenVPN, SlowDNS**
> — semua diakses lewat menu inline Telegram, tanpa perlu SSH manual.

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

## ✨ Fitur

- **🖥 Remote install** — daftarkan VPS dari Telegram, bot SSH ke VPS dan pasang stack lengkap dengan live progress.
- **🚀 ZIVPN built-in** — UDP tunnel dari [zivpn.com](https://zivpn.com), auto-DNAT range 6000-19999.
- **🔐 Multi-protocol** — SSH, VMess, VLESS, Trojan, Shadowsocks, OpenVPN, SlowDNS.
- **👥 Multi-tenant reseller** — user lain bisa daftar, top-up, kelola VPS mereka sendiri.
- **💰 Payment via Pakasir** — QRIS + Virtual Account (BCA/BNI/BRI/CIMB/Maybank/Permata), webhook auto-credit.
- **🔒 Kredensial VPS di-encrypt at rest** (Fernet AES-128 + HMAC).
- **📊 Dashboard stats** — bandwidth, users online, CPU/RAM/disk usage.
- **🆓 Trial akun** untuk client kamu.
- **🎨 Fresh branding** — 100% no third-party attribution.

---

## 🗺️ Roadmap (Milestones)

| M | Fokus | Status |
|---|-------|--------|
| **M1** | Scaffold, DB models, main menu, Pakasir client, install scripts | ✅ Done |
| **M2** | VPS wizard, SSH connection pool, install trigger, live progress streaming | 🚧 Next |
| **M3** | SSH + Xray account CRUD (create/renew/delete/list/lock/cek login) | ⏳ |
| **M4** | ZIVPN account CRUD + service control + port/password rotate | ⏳ |
| **M5** | Trial, backup ke GDrive, stats, autoreboot, settings | ⏳ |
| **M6** | Admin panel (user management, broadcast, harga per-produk, laporan) | ⏳ |
| **M7** | Payment auto-credit end-to-end + refund + faktur | ⏳ |

---

## 🚀 Setup

### Prasyarat

- **VPS terpisah** untuk bot (spec minimal: 1 vCPU, 512MB RAM, Debian/Ubuntu)
- **Domain** dengan A record ke IP bot (untuk webhook Pakasir)
- **Bot token** dari [@BotFather](https://t.me/BotFather)
- **Pakasir account** di [app.pakasir.com](https://app.pakasir.com) — bikin project, catat slug & API key
- **Telegram user ID** kamu (dari [@userinfobot](https://t.me/userinfobot))

### Instalasi (dengan Docker Compose)

```bash
# 1. Clone
git clone https://github.com/tdede914-creator/Red.git
cd Red/kobong-vpn-bot

# 2. Generate Fernet key untuk encryption
FERNET_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")

# 3. Setup .env
cp .env.example .env
nano .env
#   Isi BOT_TOKEN, SUPER_ADMIN_IDS, PAKASIR_SLUG, PAKASIR_API_KEY,
#   PUBLIC_WEBHOOK_URL, dan FERNET_KEY di atas

# 4. Run
docker compose up -d

# 5. Cek log
docker compose logs -f bot
```

### Instalasi (tanpa Docker)

```bash
sudo apt install -y python3.12 python3.12-venv
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
nano .env                     # isi semua field wajib

python -m bot
```

### Setup webhook Pakasir

Login ke [app.pakasir.com](https://app.pakasir.com) → Project → Settings → Webhook URL:

```
https://your-domain.com/webhook/pakasir
```

Set secret yang sama seperti `PAKASIR_WEBHOOK_SECRET` di `.env`.

Reverse proxy contoh (Caddyfile):

```
your-domain.com {
    reverse_proxy bot:8080
}
```

---

## 📱 Alur Pakai Bot

### Bagi kamu (super admin)

1. `/start` → cek profil kamu sudah `SUPER ADMIN`
2. **🖥 VPS → Tambah VPS Baru** → input IP + user + password/SSH key
3. **🚀 Install Stack** → pilih Full / Xray only / +ZIVPN
4. Tunggu bot selesai install (~5-10 menit dengan progress bar live)
5. Buat akun untuk client di menu protokol yang bersangkutan

### Bagi reseller kamu

1. `/start` → daftar otomatis sebagai `RESELLER`
2. **💰 Top Up Saldo** → pilih nominal → bayar via QRIS/VA lewat Pakasir
3. Setelah saldo masuk, bisa create akun di VPS kamu (atau daftarin VPS sendiri)
4. Saldo terpotong sesuai harga produk per akun

---

## 🏗 Arsitektur

```
┌─────────────┐        ┌──────────────┐        ┌───────────────┐
│Telegram User│  ──▶  │  Bot (Python) │  SSH  │  Target VPS   │
└─────────────┘        │  python-tg-bot│  ──▶  │  (Xray, SSH,  │
                       │  asyncssh     │       │   ZIVPN, dst) │
                       │  aiohttp      │       └───────────────┘
                       └──────────────┘
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
              ┌──────────┐        ┌──────────┐
              │ SQLite/PG│        │ Pakasir  │
              │ SQLAlch. │        │ webhook  │
              └──────────┘        └──────────┘
```

**Storage**: SQLite default (upgrade ke Postgres via `DATABASE_URL`).

**Security**:
- VPS credentials di-encrypt pakai Fernet sebelum masuk DB
- Bot admin roles: `SUPER_ADMIN`, `RESELLER`, `CLIENT`, `BANNED`
- Pakasir webhook di-verify pakai HMAC-SHA256

---

## 📁 Struktur Project

```
kobong-vpn-bot/
├── bot/
│   ├── __main__.py           # entry point
│   ├── config.py             # env-based config w/ validation
│   ├── db.py                 # async SQLAlchemy engine
│   ├── models.py             # User, VPS, Account, Order, Product
│   ├── crypto.py             # Fernet encrypt/decrypt
│   ├── pakasir.py            # Pakasir API client
│   ├── webhook_server.py     # aiohttp for payment callbacks
│   ├── banner.py             # KOBONG branding
│   ├── keyboards.py          # inline keyboards for all menus
│   └── handlers/
│       ├── start.py          # /start + main menu router
│       ├── vps.py            # VPS registration/list/install
│       ├── payment.py        # top-up flow
│       └── protocol_stub.py  # placeholder for protocol handlers
├── scripts/
│   ├── kobong-install.sh     # main installer (runs on target VPS)
│   ├── install_zivpn.sh      # ZIVPN UDP installer
│   └── uninstall.sh          # cleanup
├── docker-compose.yml
├── Dockerfile
├── requirements.txt
└── .env.example
```

---

## 🔐 Kredensial Bocor?

Sebelumnya di [repo Red parent](../) ada beberapa kredensial ter-hardcode
yang sudah bocor di history publik:

1. Gmail: `oceantestdigital@gmail.com` / password `jokerman77`
2. Bot token: `7117869623:AAHBmg…` (di `setup-main.sh`)
3. Bot token: `7660217485:AAHyPV…` (di `Features/menu/menu`)

**Wajib ganti/revoke**:
- Ganti password Gmail di [myaccount.google.com](https://myaccount.google.com/security)
- Revoke bot tokens di @BotFather → `/revoke` → pilih bot
- Semua kredensial di bot baru ini di-load dari `.env` (tidak pernah di-commit)

---

## 🤝 Kontribusi & Support

- Bug/feature request → buka issue di GitHub
- Update rutin → check branch `main` dan tag rilis

## 📜 Lisensi

MIT — bebas dipakai untuk keperluan pribadi maupun komersial.

---

**Made with 🌙 by KOBONG**
