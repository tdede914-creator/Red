# Setup Guide — KOBONG VPN BOT

**Bot ini pakai polling ke Pakasir (bukan webhook).** Artinya:

- ✅ **Tidak butuh domain**
- ✅ **Tidak butuh TLS certificate**
- ✅ **Tidak butuh reverse proxy (Caddy/Nginx)**
- ✅ **Bisa jalan di VPS behind NAT**

Bot cukup punya akses **outbound internet** untuk polling Pakasir tiap 10 detik.

---

## 1. Prasyarat

| | |
|---|---|
| Server bot | VPS 1 vCPU / 512 MB RAM (Ubuntu 22.04 / Debian 12 recommended) |
| Python | 3.12+ (jika tidak pakai Docker) |
| Bot token | dari [@BotFather](https://t.me/BotFather) |
| Telegram ID | dari [@userinfobot](https://t.me/userinfobot) |
| Pakasir | akun di [app.pakasir.com](https://app.pakasir.com) — buat project, catat slug & api key |

**Yang TIDAK diperlukan** (jangan buat sendiri capek):
- ~~Domain~~
- ~~SSL cert~~
- ~~Reverse proxy~~
- ~~Webhook URL~~

---

## 2. Persiapan Environment

### Generate Fernet key
```bash
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```
Simpan key ini di `FERNET_KEY`. **Kalau hilang, semua kredensial VPS di DB tidak bisa didekripsi**.

### Isi `.env`
```bash
cp .env.example .env
nano .env
```

Wajib diisi:
- `BOT_TOKEN`
- `BOT_USERNAME` (tanpa @)
- `SUPER_ADMIN_IDS` (comma-separated telegram user IDs)
- `FERNET_KEY`
- `PAKASIR_SLUG`, `PAKASIR_API_KEY` (kalau mau enable payment)

Yang bisa dibiarkan default:
- `PAKASIR_METHOD=qris`
- `PAKASIR_BASE_URL=https://app.pakasir.com`

---

## 3. Deploy (Docker Compose — Recommended)

```bash
docker compose up -d --build
docker compose logs -f bot
```

Log yang bagus:
```
[INFO] kobong: KOBONG VPN BOT v0.1.0 starting up…
[INFO] kobong.db: Database initialized
[INFO] payment_poller: Payment poller started: resumed 0 pending order(s)
[INFO] kobong: ✅ Bot online. Admin IDs: [1234567890]
[INFO] kobong: 💰 Pakasir: ENABLED (polling every 10s)
```

Restart / stop:
```bash
docker compose restart bot
docker compose down
```

---

## 4. Deploy (systemd, manual — tanpa Docker)

```bash
sudo apt install -y python3.12 python3.12-venv
python3.12 -m venv /opt/kobong-vpn-bot/.venv
cd /opt/kobong-vpn-bot
source .venv/bin/activate
pip install -r requirements.txt

# Systemd unit
sudo tee /etc/systemd/system/kobong-vpn-bot.service > /dev/null <<'EOF'
[Unit]
Description=KOBONG VPN BOT
After=network.target

[Service]
Type=simple
User=kobong
WorkingDirectory=/opt/kobong-vpn-bot
Environment=PYTHONUNBUFFERED=1
EnvironmentFile=/opt/kobong-vpn-bot/.env
ExecStart=/opt/kobong-vpn-bot/.venv/bin/python -m bot
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now kobong-vpn-bot
sudo journalctl -u kobong-vpn-bot -f
```

---

## 5. Test

1. Chat bot kamu di Telegram → `/start`
2. Cek profil kamu sebagai `SUPER ADMIN`
3. Klik **💰 Top Up Saldo → Rp 10.000 → QRIS**
4. Bot buat transaksi di Pakasir → kasih tombol "💳 Bayar Sekarang"
5. Klik tombol → buka halaman bayar Pakasir dengan QR
6. Kamu bayar (atau simulate di dashboard Pakasir)
7. Dalam maks 10 detik, bot deteksi status `completed` via polling → saldo auto-terisi + notif Telegram

## Troubleshooting

**Bot tidak respons `/start`**
- Cek `docker compose logs bot`
- Pastikan `BOT_TOKEN` valid: `curl https://api.telegram.org/bot${BOT_TOKEN}/getMe`

**Payment stuck di pending**
- Cek log bot: `docker compose logs bot | grep -i poll`
- Harusnya ada baris `Poll KBG-xxx [1/60]: status=pending` tiap 10 detik
- Kalau tidak ada → poller crash, cek stack trace di log
- Kalau ada tapi status selalu `pending`, cek langsung di dashboard Pakasir

**`FERNET_KEY placeholder error`**
- `.env` masih pakai nilai template. Generate baru pakai command di step 2.

**Database locked**
- SQLite lock issue kalau banyak concurrent writes. Migrasi ke Postgres:
  ```
  DATABASE_URL=postgresql+asyncpg://user:pass@host:5432/kobong
  ```

**Payment berhasil tapi saldo tidak nambah**
- Buka `data/kobong.db` cek tabel `orders`:
  ```bash
  docker compose exec bot python -c "
  import asyncio
  from sqlalchemy import select
  from bot.db import get_session
  from bot.models import Order
  async def main():
      async with get_session() as s:
          for o in (await s.execute(select(Order).limit(10))).scalars():
              print(o.order_ref, o.status.value, o.amount)
  asyncio.run(main())
  "
  ```
- Kalau `status=completed` tapi user balance tidak nambah → race condition, hubungi admin
