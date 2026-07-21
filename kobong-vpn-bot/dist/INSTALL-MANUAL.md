# 📦 Panduan Instalasi Manual (Upload ZIP)

Cocok kalau kamu punya file `kobong-vpn-bot.zip` yang di-upload manual
lewat SCP/SFTP/FileZilla.

---

## 🎯 Prasyarat di VPS

- Ubuntu 22.04 / Debian 12 (Ubuntu 20+ / Debian 10+ juga OK)
- Root SSH access
- Min 1 vCPU, 512 MB RAM
- Punya bahan siap:
  - Bot token dari [@BotFather](https://t.me/BotFather)
  - Telegram User ID kamu dari [@userinfobot](https://t.me/userinfobot)
  - Pakasir slug + API key (opsional)

---

## Step 1 — Upload ZIP ke VPS

Pilih salah satu cara:

### Cara A: FileZilla / WinSCP (paling gampang, klik-klik)
1. Connect ke VPS pakai IP + user `root` + password
2. Di panel kanan, masuk ke folder `/root/`
3. Drag `kobong-vpn-bot.zip` dari kiri ke kanan

### Cara B: `scp` dari terminal (Linux/Mac/Git Bash)
```bash
scp kobong-vpn-bot.zip root@<IP-VPS>:/root/
```
Ganti `<IP-VPS>` dengan IP VPS bot kamu.

### Cara C: `pscp` dari Windows CMD
```cmd
pscp kobong-vpn-bot.zip root@<IP-VPS>:/root/
```

---

## Step 2 — SSH ke VPS + Extract

Login ke VPS via SSH (Putty / terminal):
```bash
ssh root@<IP-VPS>
```

Lalu jalankan:
```bash
# 1. Install unzip kalau belum ada
apt update && apt install -y unzip

# 2. Extract ZIP ke /opt
cd /opt
unzip /root/kobong-vpn-bot.zip

# 3. Cek isinya
ls /opt/kobong-vpn-bot
# Harusnya kelihatan: bot/  scripts/  install-bot.sh  README.md  dll
```

---

## Step 3 — Jalankan Installer

```bash
cd /opt/kobong-vpn-bot
chmod +x install-bot.sh scripts/*.sh
bash install-bot.sh
```

⚠️ **Penting:** Installer akan coba `git clone` dari GitHub kalau folder belum ada.
Karena kamu sudah manual upload, installer akan skip git clone dan pakai
folder yang sudah ada (`/opt/kobong-vpn-bot`).

Installer akan **interaktif nanya**:
```
1/5 Bot token dari @BotFather:            → paste token dari BotFather
2/5 Bot username tanpa @ [KobongVpnBot]:  → contoh: KobongVpnBot
3/5 Telegram User ID admin:               → angka dari @userinfobot
4/5 Pakasir slug [kosong=skip payment]:   → skip dulu kalau belum siap
5/5 Pakasir API key:                      → hanya muncul kalau slug diisi
```

Dalam 1-2 menit installer selesai + service otomatis nyala.

---

## Step 4 — Test Bot

Log service:
```bash
tail -f /opt/kobong-vpn-bot/logs/bot.log
```

Harus muncul:
```
[INFO] kobong: KOBONG VPN BOT v0.1.0 starting up…
[INFO] kobong.db: Database initialized
[INFO] payment_poller: Payment poller started: resumed 0 pending order(s)
[INFO] kobong: ✅ Bot online. Admin IDs: [xxxxxxxxx]
[INFO] kobong: 💰 Pakasir: ENABLED (polling every 10s)
[INFO] kobong: 🔐 SSH pool size: 10
```

Buka Telegram, chat bot kamu → `/start` → harusnya muncul banner KOBONG + menu.

---

## Perintah Berguna

| Aksi | Perintah |
|------|----------|
| Cek status | `systemctl status kobong-vpn-bot` |
| Restart | `systemctl restart kobong-vpn-bot` |
| Log realtime | `tail -f /opt/kobong-vpn-bot/logs/bot.log` |
| Log via journal | `journalctl -u kobong-vpn-bot -f` |
| Edit env | `nano /opt/kobong-vpn-bot/.env` (restart service setelah edit) |
| Uninstall | `bash /opt/kobong-vpn-bot/uninstall-bot.sh` |

---

## Troubleshooting

### "Permission denied" saat run install-bot.sh
```bash
chmod +x install-bot.sh
```

### "python3.12 not found"
Installer otomatis fallback ke `python3` default. Kalau default juga tidak ada:
```bash
apt install -y python3 python3-venv python3-dev
```

### "unzip: command not found"
```bash
apt install -y unzip
```

### Service gagal start
```bash
journalctl -u kobong-vpn-bot -n 50 --no-pager
```
Kirim log-nya ke saya untuk saya bantu debug.

### Bot tidak respons `/start`
```bash
# Cek token valid
TOKEN=$(grep BOT_TOKEN /opt/kobong-vpn-bot/.env | cut -d= -f2)
curl "https://api.telegram.org/bot${TOKEN}/getMe"
```
Harus dapat `{"ok":true,...}`. Kalau `false` → token salah.

### `FERNET_KEY still placeholder` error
Buka `.env` cek `FERNET_KEY`, harusnya sudah ke-generate otomatis oleh installer.
Kalau masih placeholder:
```bash
NEW_KEY=$(/opt/kobong-vpn-bot/.venv/bin/python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
sed -i "s|^FERNET_KEY=.*|FERNET_KEY=${NEW_KEY}|" /opt/kobong-vpn-bot/.env
systemctl restart kobong-vpn-bot
```
