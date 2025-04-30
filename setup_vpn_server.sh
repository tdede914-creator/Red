#!/bin/bash

# Skrip untuk mengotomatiskan setup http_server.sh sebagai systemd service
# Untuk Ubuntu/Debian

# Variabel
SCRIPTS_DIR="/root/vpn-scripts"
LOG_FILE="/var/log/vpn-http-server.log"
SERVICE_NAME="vpn-http-server"
PORT=8080

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Fungsi untuk mencetak pesan
print_message() {
    local type=$1
    local message=$2
    if [ "$type" = "error" ]; then
        echo -e "${RED}ERROR: $message${NC}"
    elif [ "$type" = "success" ]; then
        echo -e "${GREEN}SUCCESS: $message${NC}"
    else
        echo "$message"
    fi
}

# Fungsi untuk memeriksa perintah
check_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        print_message error "$1 tidak ditemukan"
        exit 1
    fi
}

# 1. Update sistem dan install dependensi
print_message info "Mengupdate sistem dan menginstall dependensi..."
apt-get update && apt-get upgrade -y || {
    print_message error "Gagal mengupdate sistem"
    exit 1
}
apt-get install -y netcat-openbsd jq uuid-runtime curl || {
    print_message error "Gagal menginstall dependensi"
    exit 1
}

# Verifikasi dependensi
for cmd in nc jq uuidgen curl; do
    check_command "$cmd"
done
print_message success "Dependensi terinstall"

# 2. Buat direktori untuk skrip
print_message info "Membuat direktori $SCRIPTS_DIR..."
mkdir -p "$SCRIPTS_DIR" || {
    print_message error "Gagal membuat direktori $SCRIPTS_DIR"
    exit 1
}

# 3. Salin skrip ke direktori
print_message info "Menyiapkan skrip..."

# Skrip manage_account.sh
cat > "$SCRIPTS_DIR/manage_account.sh" << 'EOF'
#!/bin/bash

ACTION=$1
PROTOCOL=$2
USERNAME=$3
PASSWORD=$4
DURATION=$5
IPLIMIT=$6
QUOTA=$7
BUG=$8

# Direktori skrip
SCRIPT_DIR="/root"
CONFIG_DIR="/etc/xray"
DB_DIR="/etc"

# Fungsi untuk menjalankan skrip dan menangkap output
run_script() {
    local script=$1
    local user=$2
    local password=$3
    local iplimit=$4
    local quota=$5
    local duration=$6
    local bug=$7
    local output_file="/tmp/account_output_$user.txt"

    # Jalankan skrip dengan input yang sesuai
    if [[ "$script" == "createssh" ]]; then
        echo -e "$user\n$password\n$iplimit\n$duration" | bash "$SCRIPT_DIR/$script.sh" > "$output_file" 2>&1
    else
        echo -e "$user\n$iplimit\n$quota\n$duration\n$bug" | bash "$SCRIPT_DIR/$script.sh" > "$output_file" 2>&1
    fi

    # Baca output
    local output=$(cat "$output_file")
    rm -f "$output_file"

    # Ekstrak informasi penting dari output
    local link_tls=$(echo "$output" | grep "Link TLS" -A1 | tail -n1)
    local link_ntls=$(echo "$output" | grep "Link NTLS" -A1 | tail -n1 || echo "")
    local link_grpc=$(echo "$output" | grep "Link GRPC" -A1 | tail -n1 || echo "")
    local expiry=$(echo "$output" | grep "Berakhir Pada" -A1 | tail -n1)
    local uuid=$(echo "$output" | grep -E "id\s*:" | awk '{print $NF}' || echo "")
    local config_file=$(echo "$output" | grep "Format OpenClash" | awk '{print $NF}' || echo "")

    # Format output sebagai JSON
    echo "{\"success\": true, \"username\": \"$user\", \"uuid\": \"$uuid\", \"link_tls\": \"$link_tls\", \"link_ntls\": \"$link_ntls\", \"link_grpc\": \"$link_grpc\", \"expiry\": \"$expiry\", \"config_file\": \"$config_file\"}"
}

# Validasi input
if [[ -z "$ACTION" || -z "$PROTOCOL" || -z "$USERNAME" || -z "$DURATION" ]]; then
    echo "{\"success\": false, \"message\": \"Missing required parameters\"}"
    exit 1
fi

# Pilih skrip berdasarkan protokol
case $PROTOCOL in
    ssh)
        if [[ -z "$PASSWORD" ]]; then
            echo "{\"success\": false, \"message\": \"Password required for SSH\"}"
            exit 1
        fi
        run_script "createssh" "$USERNAME" "$PASSWORD" "$IPLIMIT" "$QUOTA" "$DURATION" "$BUG"
        ;;
    vmess)
        run_script "createvmess" "$USERNAME" "" "$IPLIMIT" "$QUOTA" "$DURATION" "$BUG"
        ;;
    vless)
        run_script "createvless" "$USERNAME" "" "$IPLIMIT" "$QUOTA" "$DURATION" "$BUG"
        ;;
    trojan)
        run_script "createtrojan" "$USERNAME" "" "$IPLIMIT" "$QUOTA" "$DURATION" "$BUG"
        ;;
    shadowsocks)
        run_script "createshadowsocks" "$USERNAME" "" "$IPLIMIT" "$QUOTA" "$DURATION" "$BUG"
        ;;
    *)
        echo "{\"success\": false, \"message\": \"Unsupported protocol: $PROTOCOL\"}"
        exit 1
        ;;
esac
EOF

# Skrip setup_api_key.sh
cat > "$SCRIPTS_DIR/setup_api_key.sh" << 'EOF'
#!/bin/bash

# File untuk menyimpan API key
API_KEY_FILE="/root/.api_key"

# Fungsi untuk mengenerate API key
generate_api_key() {
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen
    else
        cat /proc/sys/kernel/random/uuid
    fi
}

# Generate API key
API_KEY=$(generate_api_key)

# Simpan API key ke file
echo "$API_KEY" > "$API_KEY_FILE"
chmod 600 "$API_KEY_FILE"

# Tampilkan API key
echo "API Key telah digenerate dan disimpan di $API_KEY_FILE"
echo "API Key: $API_KEY"
echo "Catat API key ini untuk digunakan di Cloudflare Workers saat menambah server."
EOF

# Skrip http_server.sh
cat > "$SCRIPTS_DIR/http_server.sh" << 'EOF'
#!/bin/bash

# File API key
API_KEY_FILE="/root/.api_key"
PORT=8080

# Baca API key
if [[ ! -f "$API_KEY_FILE" ]]; then
    echo "Error: File API key ($API_KEY_FILE) tidak ditemukan. Jalankan setup_api_key.sh terlebih dahulu."
    exit 1
fi
API_KEY=$(cat "$API_KEY_FILE")

# Fungsi untuk mengirim respons HTTP
send_response() {
    local status=$1
    local body=$2
    echo -e "HTTP/1.1 $status\r\nContent-Type: application/json\r\n\r\n$body"
}

# Fungsi untuk memvalidasi header Authorization
validate_auth() {
    local auth_header=$1
    if [[ "$auth_header" != "Bearer $API_KEY" ]]; then
        send_response "401 Unauthorized" "{\"success\": false, \"message\": \"Unauthorized\"}"
        return 1
    fi
    return 0
}

# Fungsi untuk memproses request
process_request() {
    local method=$1
    local path=$2
    local headers=$3
    local body=$4

    # Ekstrak header Authorization
    local auth_header=$(echo "$headers" | grep -i "^Authorization:" | cut -d' ' -f2-)

    # Tangani endpoint /ping
    if [[ "$method" == "GET" && "$path" == "/ping" ]]; then
        if ! validate_auth "$auth_header"; then
            return
        fi
        send_response "200 OK" "{\"success\": true, \"message\": \"Server is alive\"}"
        return
    fi

    # Tangani endpoint /execute
    if [[ "$method" != "POST" || "$path" != "/execute" ]]; then
        send_response "404 Not Found" "{\"success\": false, \"message\": \"Not found\"}"
        return
    fi

    if ! validate_auth "$auth_header"; then
        return
    fi

    # Parse body JSON untuk mendapatkan perintah
    local command=$(echo "$body" | jq -r '.command // empty')
    if [[ -z "$command" ]]; then
        send_response "400 Bad Request" "{\"success\": false, \"message\": \"Command required\"}"
        return
    fi

    # Jalankan perintah
    local output_file="/tmp/server_output_$$.txt"
    bash -c "$command" > "$output_file" 2>&1
    local output=$(cat "$output_file")
    rm -f "$output_file"

    # Validasi output sebagai JSON
    if ! echo "$output" | jq . >/dev/null 2>&1; then
        send_response "500 Internal Server Error" "{\"success\": false, \"message\": \"Invalid script output\"}"
        return
    fi

    # Kirim output
    send_response "200 OK" "$output"
}

# Main loop untuk menjalankan server
while true; do
    # Baca request menggunakan netcat
    {
        read -r request_line
        method=$(echo "$request_line" | cut -d' ' -f1)
        path=$(echo "$request_line" | cut -d' ' -f2)
        headers=""
        body=""
        content_length=0

        # Baca header
        while read -r line && [[ "$line" != $'\r' ]]; do
            headers+="$line\n"
            if [[ "$line" =~ Content-Length:\ ([0-9]+) ]]; then
                content_length=${BASH_REMATCH[1]}
            fi
        done

        # Baca body sesuai Content-Length
        if [[ $content_length -gt 0 ]]; then
            body=$(head -c "$content_length")
        fi

        # Proses request
        process_request "$method" "$path" "$headers" "$body"
    } | nc -l -p "$PORT" -q 1
done
EOF

# Beri izin eksekusi
chmod +x "$SCRIPTS_DIR"/*.sh || {
    print_message error "Gagal memberikan izin eksekusi pada skrip"
    exit 1
}
print_message success "Skrip disiapkan di $SCRIPTS_DIR"

# 4. Generate API key
print_message info "Mengenerate API key..."
bash "$SCRIPTS_DIR/setup_api_key.sh" | tee /tmp/api_key_output.txt || {
    print_message error "Gagal mengenerate API key"
    exit 1
}
API_KEY=$(grep "API Key:" /tmp/api_key_output.txt | cut -d' ' -f3)
print_message success "API key digenerate: $API_KEY"

# 5. Buat systemd service
print_message info "Membuat systemd service..."
cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=VPN HTTP Server for Managing VPN Accounts
After=network.target

[Service]
ExecStart=/bin/bash $SCRIPTS_DIR/http_server.sh
Restart=always
RestartSec=5
User=root
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd dan aktifkan service
systemctl daemon-reload || {
    print_message error "Gagal reload systemd"
    exit 1
}
systemctl enable $SERVICE_NAME.service || {
    print_message error "Gagal mengaktifkan service"
    exit 1
}
systemctl start $SERVICE_NAME.service || {
    print_message error "Gagal menjalankan service"
    exit 1
}

# Verifikasi status service
sleep 2
if systemctl is-active --quiet $SERVICE_NAME.service; then
    print_message success "Service $SERVICE_NAME berjalan"
else
    print_message error "Service $SERVICE_NAME gagal berjalan. Periksa log di $LOG_FILE"
    exit 1
fi

# 6. Konfigurasi firewall
print_message info "Mengatur firewall..."
ufw allow $PORT || {
    print_message error "Gagal membuka port $PORT"
    exit 1
}
ufw status | grep -q "$PORT" && print_message success "Port $PORT terbuka"

# 7. Konfigurasi logging
print_message info "Mengatur logging..."
touch "$LOG_FILE" && chmod 644 "$LOG_FILE" || {
    print_message error "Gagal membuat file log $LOG_FILE"
    exit 1
}
cat > /etc/logrotate.d/$SERVICE_NAME << EOF
$LOG_FILE {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 644 root root
}
EOF
print_message success "Logging diatur di $LOG_FILE"

# 8. Instruksi untuk pengguna
print_message success "Setup selesai!"
echo
echo "Instruksi selanjutnya:"
echo "1. Tambahkan server di Cloudflare Workers atau bot Telegram:"
echo "   - Nama Server: <pilih nama, misalnya 'server1'>"
echo "   - Host: <IP VPS Anda, misalnya '$(curl -s ifconfig.me)'>"
echo "   - API Key: $API_KEY"
echo "   - Harga: <misalnya 50000 untuk Rp 50.000/30 hari>"
echo "   - Batas IP: <misalnya 2>"
echo "   - Kuota: <misalnya 10000 untuk 10GB>"
echo "   Contoh perintah Telegram:"
echo "   /addserver server1 $(curl -s ifconfig.me) $API_KEY 50000 2 10000"
echo "2. Uji koneksi ke server untuk memastikan server terhubung:"
echo "   curl -H \"Authorization: Bearer $API_KEY\" http://$(curl -s ifconfig.me):$PORT/ping"
echo "   Respons yang diharapkan:"
echo "   {\"success\": true, \"message\": \"Server is alive\"}"
echo "3. Pastikan skrip pendukung (createtrojan.sh, dll.) ada di /root/"
echo "4. Uji endpoint /execute:"
echo "   curl -X POST http://$(curl -s ifconfig.me):$PORT/execute \\"
echo "   -H \"Authorization: Bearer $API_KEY\" \\"
echo "   -H \"Content-Type: application/json\" \\"
echo "   -d '{\"command\":\"bash $SCRIPTS_DIR/manage_account.sh new trojan testuser \\\"\\\" 30 2 10000 bug.com\"}'"
echo "5. Periksa log jika ada masalah: cat $LOG_FILE"
echo
print_message warning "CATATAN: Skrip pendukung VPN (createtrojan.sh, dll.) harus disediakan di /root/. Jika belum ada, sesuaikan dengan konfigurasi VPN Anda."
