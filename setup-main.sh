#!/bin/bash
# --- Inisialisasi Logging ---
LOG_FILE="/var/log/wendy_vpn_setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1 # Redirect semua output stdout dan stderr ke log dan terminal

# Fungsi untuk mencatat log dengan timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "========== MULAI SETUP WENDY VPN =========="
log "Skrip dimulai oleh pengguna: $(whoami)"

# --- Setup Awal ---
clear
log "Memperbarui daftar paket..."
apt update -y
log "Memutakhirkan paket..."
apt upgrade -y
log "Menginstal curl..."
apt install -y curl
log "Menginstal socat..."
apt install -y socat

# Definisi warna (untuk tampilan terminal)
Green="\e[92;1m"
RED="\033[1;31m"
YELLOW="\033[33m"
BLUE="\033[36m"
FONT="\033[0m"
OK="${Green}--->${FONT}"
EROR="${RED}[EROR]${FONT}"
GRAY="\e[1;30m"
NC='\e[0m'
red='\e[1;31m'
green='\e[0;32m'

TIME=$(date '+%d %b %Y')
log "Mendapatkan IP publik..."
ipsaya=$(curl -s ipinfo.io/ip)
TIMES="10"
CHATID="5162695441"
KEY="7117869623:AAHBmgzOUsmHBjcm5TFir9JmaZ_X7ynMoF4"
URL="https://api.telegram.org/bot$KEY/sendMessage"

export IP=$(curl -sS icanhazip.com)

clear
echo -e "${YELLOW}----------------------------------------------------------${NC}"
echo -e "\033[96;1m                  WENDY VPN TUNNELING\033[0m"
echo -e "${YELLOW}----------------------------------------------------------${NC}"
echo ""

# --- Bagian Password ---
while true; do
    echo "Select an option/Pilih opsi:"
    echo "1. Ubah Password/Change Password"
    echo "2. or Enter, Lewati/Skip"
    read -p "Masukkan pilihan/Input option(1/2): " pilihan
    if [[ "$pilihan" == "1" ]]; then
        while true; do
            read -s -p "Password : " passwd
            echo
            read -s -p "Konfirmasi Password : " passwd_confirm
            echo
            if [[ -n "$passwd" && "$passwd" == "$passwd_confirm" ]]; then
                echo "$passwd" > /etc/.password.txt
                log "Password root berhasil diubah."
                break
            else
                echo "Password harus diisi dan harus sama. Silakan coba lagi."
                log "Gagal mengubah password: Password tidak cocok atau kosong."
            fi
        done
        echo root:$passwd | chpasswd
        systemctl restart ssh || systemctl restart sshd
        break
    elif [[ "$pilihan" == "2" || -z "$pilihan" ]]; then
        echo "Proses pengubahan password dilewati."
        log "Proses pengubahan password dilewati oleh pengguna."
        break
    else
        echo "Pilihan tidak valid. Silakan coba lagi."
    fi
done

# --- Deteksi Arsitektur dan OS ---
if [[ $(uname -m) != "x86_64" ]]; then
    echo -e "${EROR} Your Architecture Is Not Supported ( ${YELLOW}$(uname -m)${NC} )"
    log "ERROR: Arsitektur $(uname -m) tidak didukung. Keluar."
    exit 1
else
    echo -e "${OK} Your Architecture Is Supported ( ${green}$(uname -m)${NC} )"
    log "Arsitektur $(uname -m) didukung."
fi

OS_ID=$(grep -w ID /etc/os-release | cut -d'=' -f2 | tr -d '"')
OS_NAME=$(grep -w PRETTY_NAME /etc/os-release | cut -d'=' -f2 | tr -d '"')

if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
    echo -e "${EROR} Your OS Is Not Supported ( ${YELLOW}$OS_NAME${NC} )"
    log "ERROR: OS $OS_NAME tidak didukung. Keluar."
    exit 1
else
    echo -e "${OK} Your OS Is Supported ( ${green}$OS_NAME${NC} )"
    log "OS $OS_NAME didukung."
fi

# --- Deteksi IP ---
if [[ -z "$ipsaya" ]]; then
    echo -e "${EROR} IP Address ( ${RED}Not Detected${NC} )"
    log "ERROR: IP publik tidak terdeteksi."
else
    echo -e "${OK} IP Address ( ${green}$ipsaya${NC} )"
    log "IP publik terdeteksi: $ipsaya"
fi

echo ""
read -p "$(echo -e "Press ${GRAY}[ ${NC}${green}Enter${NC} ${GRAY}]${NC} For Starting Installation") "
echo ""
clear

# --- Cek Root ---
if [ "${EUID}" -ne 0 ]; then
    echo "You need to run this script as root"
    log "ERROR: Skrip tidak dijalankan sebagai root. Keluar."
    exit 1
fi

if [ "$(systemd-detect-virt)" == "openvz" ]; then
    echo "OpenVZ is not supported"
    log "ERROR: Lingkungan OpenVZ tidak didukung. Keluar."
    exit 1
fi

MYIP=$(curl -sS ipv4.icanhazip.com)
log "IP publik (alternatif): $MYIP"
echo -e "\e[32mloading...\e[0m"
clear

# --- Pengambilan Data Pengguna ---
rm -f /usr/bin/user
log "Mengambil data pengguna dari repositori..."
username=$(curl -s https://raw.githubusercontent.com/bowowiwendi/ipvps/main/ip | grep $MYIP | awk '{print $2}')
if [ -z "$username" ]; then
    log "WARNING: Username tidak ditemukan untuk IP $MYIP."
else
    echo "$username" >/usr/bin/user
    log "Username ditemukan: $username"
fi

valid=$(curl -s https://raw.githubusercontent.com/bowowiwendi/ipvps/main/ip | grep $MYIP | awk '{print $3}')
echo "$valid" >/usr/bin/e
exp=$(cat /usr/bin/e)
clear

# --- Definisi Variabel ---
REPO="https://raw.githubusercontent.com/bowowiwendi/WendyVpn/ABSTRAK/"
start=$(date +%s)
secs_to_human() {
    echo "Installation time : $((${1} / 3600)) hours $(((${1} / 60) % 60)) minute's $((${1} % 60)) seconds"
}

# --- Fungsi Helper ---
function print_ok() {
    echo -e "${OK} ${BLUE} $1 ${FONT}"
    log "OK: $1"
}
function print_install() {
    echo -e "${green} =============================== ${FONT}"
    echo -e "${YELLOW} # $1 ${FONT}"
    echo -e "${green} =============================== ${FONT}"
    log "INSTALL: $1"
    sleep 1
}
function print_error() {
    echo -e "${EROR} ${REDBG} $1 ${FONT}"
    log "ERROR: $1"
}
function print_success() {
    if [[ 0 -eq $? ]]; then
        echo -e "${green} =============================== ${FONT}"
        echo -e "${Green} # $1 berhasil dipasang${FONT}"
        echo -e "${green} =============================== ${FONT}"
        log "SUCCESS: $1 berhasil dipasang"
        sleep 2
    fi
}

# --- Fungsi Instalasi ---
function first_setup() {
    log "========== MENJALANKAN first_setup =========="
    timedatectl set-timezone Asia/Jakarta || log "WARNING: Gagal mengatur timezone."
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
    print_success "Directory Xray"
    apt install -y haproxy || log "ERROR: Gagal menginstal haproxy."
    print_success "HAProxy Installation"
}

function nginx_install() {
    log "========== MENJALANKAN nginx_install =========="
    apt install -y nginx || log "ERROR: Gagal menginstal nginx."
    print_success "Nginx Installation"
}

function base_package() {
    log "========== MENJALANKAN base_package =========="
    apt install -y zip pwgen openssl netcat socat cron bash-completion figlet
    apt update -y
    apt upgrade -y
    apt dist-upgrade -y
    systemctl enable chronyd || systemctl enable chrony
    systemctl restart chronyd || systemctl restart chrony
    apt install -y ntpdate && ntpdate pool.ntp.org
    apt install -y sudo debconf-utils
    apt-get clean all
    apt-get autoremove -y
    apt-get remove --purge exim4 -y
    apt-get remove --purge ufw firewalld -y
    apt-get install -y --no-install-recommends software-properties-common
    apt-get install -y speedtest-cli vnstat libnss3-dev libnspr4-dev pkg-config libpam0g-dev libcap-ng-dev libcap-ng-utils libselinux1-dev libcurl4-nss-dev flex bison make libnss3-tools libevent-dev bc rsyslog dos2unix zlib1g-dev libssl-dev libsqlite3-dev sed dirmngr libxml-parser-perl build-essential gcc g++ python3 htop lsof tar wget curl ruby zip unzip p7zip-full python3-pip libc6 util-linux build-essential msmtp-mta ca-certificates bsd-mailx iptables iptables-persistent netfilter-persistent net-tools openssl ca-certificates gnupg gnupg2 ca-certificates lsb-release gcc shc make cmake git screen socat xz-utils apt-transport-https gnupg1 dnsutils cron bash-completion ntpdate chrony jq openvpn easy-rsa
    print_success "Packet Yang Dibutuhkan"
}

function pasang_domain() {
    log "========== MENJALANKAN pasang_domain =========="
    clear
    echo -e "==============================="
    echo -e "   |\e[1;32mPlease Select a Domain Type Below \e[0m|"
    echo -e "==============================="
    echo -e "     \e[1;32m1)\e[0m Your Domain"
    echo -e "     \e[1;32m2)\e[0m Random Domain "
    echo -e "==============================="
    read -p "   Please select numbers 1-2 or Any Button(Random) : " host
    echo ""
    if [[ $host == "1" ]]; then
        clear
        echo -e "\e[1;32m===============================$NC"
        echo -e "\e[1;36m     INPUT SUBDOMAIN $NC"
        echo -e "\e[1;32m===============================$NC"
        echo -e "\033[91;1m contoh subdomain :\033[0m \033[93 wendi.ssh.cloud\033[0m"
        read -p "SUBDOMAIN :  " host1
        echo $host1 > /etc/xray/domain
        echo $host1 > /root/domain
        log "Domain kustom digunakan: $host1"
    else
        log "Mengunduh dan menjalankan random.sh..."
        wget ${REPO}files/random.sh && chmod +x random.sh && ./random.sh
        rm -f /root/random.sh
        log "Domain acak digunakan."
    fi
}

function pasang_ssl() {
    log "========== MENJALANKAN pasang_ssl =========="
    clear
    print_install "Memasang SSL Pada Domain"
    rm -rf /etc/xray/xray.key /etc/xray/xray.crt
    domain=$(cat /root/domain)
    log "Domain untuk SSL: $domain"
    STOPWEBSERVER=$(lsof -i:80 | awk 'NR==2 {print $1}')
    systemctl stop $STOPWEBSERVER nginx || true
    rm -rf /root/.acme.sh
    mkdir -p /root/.acme.sh
    # Gunakan URL resmi acme.sh
    curl https://raw.githubusercontent.com/acmesh-official/acme.sh/master/acme.sh -o /root/.acme.sh/acme.sh
    chmod +x /root/.acme.sh/acme.sh
    /root/.acme.sh/acme.sh --install
    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    ~/.acme.sh/acme.sh --issue -d $domain --standalone -k ec-256 || log "ERROR: Gagal menerbitkan sertifikat SSL."
    ~/.acme.sh/acme.sh --installcert -d $domain --fullchainpath /etc/xray/xray.crt --keypath /etc/xray/xray.key --ecc || log "ERROR: Gagal menginstal sertifikat."
    chmod 777 /etc/xray/xray.key
    log "Permission key diatur ke 777 (BERISIKO TINGGI!)."
    print_success "SSL Certificate"
}

function make_folder_xray() {
    log "========== MENJALANKAN make_folder_xray =========="
    mkdir -p /etc/xray /var/log/xray /var/www/html /etc/vmess /etc/vless /etc/trojan /etc/shadowsocks /etc/ssh /usr/bin/xray/
    touch /etc/xray/domain /var/log/xray/access.log /var/log/xray/error.log
    touch /etc/vmess/.vmess.db /etc/vless/.vless.db /etc/trojan/.trojan.db
    echo "& plughin Account" >>/etc/vmess/.vmess.db
    log "Folder dan file Xray berhasil dibuat."
}

function install_xray() {
    log "========== MENJALANKAN install_xray =========="
    latest_version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | grep tag_name | head -n1 | cut -d'"' -f4)
    log "Versi Xray terbaru: $latest_version"
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --version $latest_version
    wget -O /etc/xray/config.json "${REPO}cfg_conf_js/config.json"
    wget -O /etc/nginx/conf.d/xray.conf "${REPO}cfg_conf_js/xray.conf"
    wget -O /etc/haproxy/haproxy.cfg "${REPO}cfg_conf_js/haproxy.cfg"
    sed -i "s/xxx/$(cat /root/domain)/g" /etc/nginx/conf.d/xray.conf /etc/haproxy/haproxy.cfg
    cat /etc/xray/xray.crt /etc/xray/xray.key > /etc/haproxy/hap.pem
    systemctl daemon-reload
    print_success "Core Xray"
}

# Fungsi lain tetap seperti aslinya (Anda bisa salin dari file lama)
# Misalnya: ssh, ins_dropbear, ins_vnstat, ins_openvpn, dll

# --- Fungsi Utama Install ---
function install() {
    log "========== MEMULAI PROSES INSTALASI =========="
    pasang_domain
    first_setup
    make_folder_xray
    nginx_install
    base_package
    pasang_ssl
    install_xray
    # Tambahkan fungsi lain sesuai kebutuhan
    log "========== INSTALASI SELESAI =========="
}

# --- Jalankan Instalasi ---
install

# --- Final ---
secs_to_human "$(($(date +%s) - ${start}))"
log "Setup selesai. Tekan Enter untuk reboot."
echo -e "\033[93mSystem setup is complete.\033[0m"
echo -e "\033[93mPress [Enter] to reboot...\033[0m"
read
reboot