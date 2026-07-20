# Setup Guide — KOBONG VPN BOT

## 1. Prasyarat

| | |
|---|---|
| Server bot | VPS 1 vCPU / 512 MB RAM (Ubuntu 22.04 recommended) |
| Domain (optional) | untuk webhook Pakasir TLS (e.g. bot.example.com) |
| Python | 3.12+ (jika tidak pakai Docker) |
| Bot token | dari [@BotFather](https://t.me/BotFather) |
| Telegram ID | dari [@userinfobot](https://t.me/userinfobot) |
| Pakasir | akun di [app.pakasir.com](https://app.pakasir.com) — buat project |

## 2. Persiapan Environment

### Generate Fernet key
```bash
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```
Simpan key ini di `FERNET_KEY`. **Kalau hilang, semua kredensial VPS di DB tidak bisa didekripsi**.

### Buat `.env`
```bash
cp .env.example .env
```

Wajib diisi:
- `BOT_TOKEN`
- `BOT_USERNAME` (tanpa @)
- `SUPER_ADMIN_IDS` (comma-separated telegram user IDs)
- `FERNET_KEY`
- `PAKASIR_SLUG`, `PAKASIR_API_KEY` (kalau mau enable payment)
- `PAKASIR_WEBHOOK_SECRET`
- `PUBLIC_WEBHOOK_URL` (e.g. `https://bot.example.com`)

## 3. Deploy (Docker Compose)

```bash
docker compose up -d
docker compose logs -f bot
```

Cek health:
```bash
curl http://localhost:8080/health
# {"ok": true, "service": "kobong-vpn-bot"}
```

## 4. Deploy (systemd, manual)

```bash
# Setup venv
sudo apt install -y python3.12 python3.12-venv
python3.12 -m venv /opt/kobong-vpn-bot/.venv
source /opt/kobong-vpn-bot/.venv/bin/activate
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

## 5. Reverse Proxy (Caddy — auto TLS)

```
bot.example.com {
    reverse_proxy 127.0.0.1:8080
}
```

Simpan sebagai `/etc/caddy/Caddyfile`, `systemctl reload caddy`.

## 6. Konfigurasi Pakasir Webhook

Login → project → Settings → Webhook URL:

```
https://bot.example.com/webhook/pakasir
```

Copy webhook secret ke `PAKASIR_WEBHOOK_SECRET` di `.env`.

## 7. Test

1. Buka Telegram, chat bot → `/start`
2. Cek profil kamu sebagai `SUPER ADMIN`
3. Klik `💰 Top Up Saldo → Rp 10.000 → QRIS`
4. Cek muncul QR/link Pakasir
5. Bayar (atau pakai `simulate_payment` endpoint untuk testing)
6. Bot harus terima webhook & auto-credit saldo

## Troubleshooting

**Bot tidak respons `/start`**
- Cek `docker compose logs bot`
- Pastikan `BOT_TOKEN` valid
- Cek koneksi keluar ke `api.telegram.org`

**Webhook 401**
- `PAKASIR_WEBHOOK_SECRET` mismatch antara `.env` dan dashboard Pakasir

**`FERNET_KEY placeholder error`**
- `.env` masih pakai nilai template. Generate baru pakai command di step 2.

**Database locked**
- SQLite lock issue kalau banyak concurrent writes. Migrasi ke Postgres:
  ```
  DATABASE_URL=postgresql+asyncpg://user:pass@host:5432/kobong
  ```
