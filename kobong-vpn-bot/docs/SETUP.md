# Setup Guide — KOBONG VPN BOT

Bot ini pakai **systemd + Python venv**, tanpa Docker. Tidak butuh domain, TLS cert, atau reverse proxy karena payment pakai polling.

---

## 📋 Yang Harus Disiapkan Dulu

Ambil dulu SEMUA ini sebelum SSH ke VPS bot (biar gak bolak-balik):

| # | Bahan | Cara Ambil |
|---|-------|------------|
| 1 | **VPS untuk bot** | Ubuntu 22.04 / Debian 12, min 1 vCPU + 512 MB RAM. **Pisah dari VPS target VPN.** |
| 2 | **Bot Token Telegram** | Chat [@BotFather](https://t.me/BotFather) → `/newbot` → nama → username → dapat token `1234567890:AAH...` |
| 3 | **Telegram User ID kamu** | Chat [@userinfobot](https://t.me/userinfobot) → auto-reply ID |
| 4 | **Akun Pakasir** (opsional, buat payment) | Daftar di [pakasir.com](https://pakasir.com) → buat project → catat **slug** + **API key** |

**Yang TIDAK diperlukan:**
- ~~Domain~~ ~~SSL cert~~ ~~Reverse proxy~~ ~~Webhook URL~~

---

## 🚀 Instalasi (Satu Baris)

SSH sebagai root ke VPS bot, lalu:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tdede914-creator/Red/feat/kobong-vpn-bot-m1/kobong-vpn-bot/install-bot.sh)
```

Installer bakal:
1. Deteksi OS & install python3.12 + git + build tools
2. Clone repo ke `/opt/kobong-vpn-bot`
3. Bikin virtualenv + install requirements
4. Prompt kamu untuk 4 field: bot token, username, admin ID, Pakasir creds
5. Auto-generate `FERNET_KEY`
6. Tulis `.env` (permissions 600)
7. Bikin user sistem `kobong` + systemd unit
8. Enable + start service

Setelah selesai, kamu bakal lihat:

```
✅ KOBONG VPN BOT terinstall!

  Install dir : /opt/kobong-vpn-bot
  Service     : kobong-vpn-bot
  Env file    : /opt/kobong-vpn-bot/.env
  Log file    : /opt/kobong-vpn-bot/logs/bot.log
```

---

## ✅ Test

1. Chat bot kamu di Telegram → `/start`
2. Cek banner KOBONG muncul + status `👑 SUPER ADMIN`
3. Klik **🖥 VPS: [➕ Tambah VPS]** → wizard 6-step
4. Setelah VPS ter-registered → klik **🚀 Install Stack** → tunggu progress bar
5. Setelah "✅ Selesai!", coba:
   - **🔐 SSH → Buat Akun** → username + durasi → dapat config text
   - **🚀 ZIVPN → Buat Akun** → label + durasi → dapat config

---

## 🐛 Troubleshooting

### Cek log
```bash
tail -f /opt/kobong-vpn-bot/logs/bot.log
# atau
journalctl -u kobong-vpn-bot -f
```

### Bot tidak respons `/start`
```bash
systemctl status kobong-vpn-bot
grep BOT_TOKEN /opt/kobong-vpn-bot/.env
curl "https://api.telegram.org/bot$(grep BOT_TOKEN /opt/kobong-vpn-bot/.env | cut -d= -f2)/getMe"
```
Kalau `getMe` return `{"ok":true,...}` → token valid. Kalau `false` → token salah/di-revoke.

### `pydantic.ValidationError` di log
Env belum lengkap. Cek `.env`:
```bash
cat /opt/kobong-vpn-bot/.env | grep -v '^#' | grep -v '^$'
```
Harus ada minimal `BOT_TOKEN`, `SUPER_ADMIN_IDS`, `FERNET_KEY`.

### `FERNET_KEY placeholder error`
Env `.env` masih pakai `CHANGE_ME_TO_A_REAL_FERNET_KEY`. Fix:
```bash
NEW_KEY=$(/opt/kobong-vpn-bot/.venv/bin/python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
sed -i "s|^FERNET_KEY=.*|FERNET_KEY=${NEW_KEY}|" /opt/kobong-vpn-bot/.env
systemctl restart kobong-vpn-bot
```
Note: kalau kamu sudah pernah add VPS, kredensial di DB tidak bisa didekripsi setelah key diganti. Hapus DB:
```bash
rm /opt/kobong-vpn-bot/data/kobong.db
systemctl restart kobong-vpn-bot
```

### Install VPS gagal / stuck di stage tertentu
Cek log install di VPS target:
```bash
ssh root@<target-vps>
tail -100 /var/log/kobong-install.log
```

### SSH ke target VPS gagal dari bot
- Cek target VPS OS: `cat /etc/os-release` — harus Ubuntu 20+ / Debian 10+
- Cek firewall di target: port SSH terbuka (`ufw status`)
- Coba manual dari VPS bot: `ssh -o StrictHostKeyChecking=no root@<ip>`

### Payment stuck di pending
Cek log:
```bash
tail -f /opt/kobong-vpn-bot/logs/bot.log | grep -i poll
```
Harusnya muncul `Poll KBG-xxx [n/60]: status=pending` tiap 10 detik. Kalau tidak ada, poller crash.

### ZIVPN service tidak start di target VPS
```bash
ssh root@<target-vps>
journalctl -u kobong-zivpn -n 50 --no-pager
cat /etc/kobong/zivpn/config.json | jq .
```

---

## 🔧 Perintah Rutin

```bash
# Restart bot
systemctl restart kobong-vpn-bot

# Update dari GitHub
cd /opt/kobong-vpn-bot
sudo -u kobong git pull
sudo -u kobong /opt/kobong-vpn-bot/.venv/bin/pip install -r requirements.txt
systemctl restart kobong-vpn-bot

# Backup
sudo tar czf ~/kobong-backup-$(date +%Y%m%d).tar.gz -C /opt/kobong-vpn-bot data .env

# Edit env (misal ubah harga)
sudo nano /opt/kobong-vpn-bot/.env
sudo systemctl restart kobong-vpn-bot

# Uninstall bot (interaktif — nanya mau backup data atau tidak)
sudo bash /opt/kobong-vpn-bot/uninstall-bot.sh
```

---

## 🎛️ Konfigurasi Lanjutan (Edit `.env`)

```dotenv
# Harga per 30 hari (Rupiah). Diproporsionalkan otomatis untuk durasi lain.
DEFAULT_PRICE_SSH=5000
DEFAULT_PRICE_ZIVPN=10000

# Concurrent SSH sessions max
SSH_POOL_SIZE=10

# DEBUG untuk troubleshooting lebih detail
LOG_LEVEL=INFO   # DEBUG / INFO / WARNING / ERROR
```

Setelah edit, `systemctl restart kobong-vpn-bot`.
