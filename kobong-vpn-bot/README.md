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
- **💰 Payment via Pakasir (polling — no webhook)** — QRIS + Virtual Account, bot auto-cek tiap 10s, auto-credit saldo.
- **🔒 Kredensial VPS di-encrypt at rest** (Fernet AES-128 + HMAC).
- **📊 Dashboard stats** — bandwidth, users online, CPU/RAM/disk usage.
- **🆓 Trial akun** untuk client kamu.
- **🎨 Fresh branding** — 100% no third-party attribution.
- **📦 Zero-config deployment** — no domain, no TLS, no reverse proxy needed.

---

## 🗺️ Roadmap

| M | Fokus | Status |
|---|-------|--------|
| **M1** | Scaffold, DB, menu, Pakasir polling, install scripts | ✅ Done |
| **M2** | VPS wizard, SSH pool, install trigger, live progress | 🚧 Next |
| **M3** | SSH + Xray account CRUD | ⏳ |
| **M4** | ZIVPN account CRUD + service control | ⏳ |
| **M5** | Trial, backup, stats, settings | ⏳ |
| **M6** | Admin panel | ⏳ |
| **M7** | Payment polish (faktur, refund, custom amount) | ⏳ |

---

## 🚀 Setup Cepat

### Prasyarat

- **VPS untuk bot** (Ubuntu 22.04 / Debian 12, min 1 vCPU + 512MB RAM)
- **Bot token** dari [@BotFather](https://t.me/BotFather)
- **Telegram user ID** kamu (dari [@userinfobot](https://t.me/userinfobot))
- **Pakasir account** di [app.pakasir.com](https://app.pakasir.com)

**Yang TIDAK diperlukan:** ~~Domain~~ ~~SSL cert~~ ~~Reverse proxy~~ ~~Webhook~~ — bot pakai polling.

### Instalasi (Docker Compose)

```bash
git clone https://github.com/tdede914-creator/Red.git
cd Red/kobong-vpn-bot

# Generate Fernet key
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"

cp .env.example .env
nano .env    # isi BOT_TOKEN, SUPER_ADMIN_IDS, FERNET_KEY, PAKASIR_SLUG, PAKASIR_API_KEY

docker compose up -d --build
docker compose logs -f bot
```

Detail lengkap step-by-step ada di **[docs/SETUP.md](docs/SETUP.md)**.

---

## 💰 Cara Kerja Payment (Pakasir Polling)

```
1. User klik: Top Up Saldo → Rp 10.000 → QRIS
2. Bot call Pakasir.createPayment() → dapat QR + payment URL
3. Bot kirim link/QR ke user + start background poller
4. User bayar via aplikasi bank/e-wallet
5. Setiap 10 detik, bot GET /api/transactiondetail
6. Status berubah jadi "completed" → bot auto-credit saldo user + kirim notif
```

**Kenapa polling bukan webhook?** Karena tidak butuh:
- Domain publik
- TLS certificate
- Reverse proxy
- Konfigurasi webhook di dashboard Pakasir

Bot cukup punya akses outbound internet. Lengkap: **[docs/PAYMENT.md](docs/PAYMENT.md)**.

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
3. Setelah saldo masuk otomatis, bisa create akun di VPS kamu (atau daftarin VPS sendiri)
4. Saldo terpotong sesuai harga produk per akun

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
│   ├── pakasir.py            # Pakasir API client (polling)
│   ├── payment_poller.py     # background payment status poller
│   ├── banner.py             # KOBONG branding
│   ├── keyboards.py          # inline keyboards for all menus
│   └── handlers/
│       ├── start.py          # /start + main menu router
│       ├── vps.py            # VPS registration/list/install
│       ├── payment.py        # top-up flow (uses poller)
│       └── protocol_stub.py  # placeholder for protocol handlers
├── scripts/
│   ├── kobong-install.sh     # main installer (runs on target VPS)
│   ├── install_zivpn.sh      # ZIVPN UDP installer
│   └── uninstall.sh          # cleanup
├── docs/
│   ├── SETUP.md              # step-by-step install
│   ├── PAYMENT.md            # payment polling flow
│   ├── ARCHITECTURE.md       # data model + diagram
│   └── ROADMAP.md            # milestones
├── docker-compose.yml
├── Dockerfile
├── requirements.txt
└── .env.example
```

---

## 🔐 Kredensial Bocor di Parent Repo

Sebelumnya di [repo Red parent](../) ada kredensial ter-hardcode yang sudah bocor:

1. Gmail: `oceantestdigital@gmail.com` / password `jokerman77`
2. Bot token: `7117869623:AAHBmg…` (di `setup-main.sh`)
3. Bot token: `7660217485:AAHyPV…` (di `Features/menu/menu`)

**Wajib revoke:**
- Ganti password Gmail di [myaccount.google.com](https://myaccount.google.com/security)
- Revoke bot tokens di @BotFather → `/revoke`

Bot baru ini semua kredensial di-load dari `.env` (tidak pernah di-commit).

---

## 📜 Lisensi

MIT — bebas dipakai untuk keperluan pribadi maupun komersial.

---

**Made with 🌙 by KOBONG**
