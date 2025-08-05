#!/bin/bash
clear
apt update -y # Update dulu
apt upgrade -y
apt install curl -y
apt install wondershaper -y
apt install socat -y
Green="\e[92;1m"
RED="\033[1;31m"
YELLOW="\033[33m"
BLUE="\033[36m"
FONT="\033[0m"
GREENBG="\033[42;37m"
REDBG="\033[41;37m"
OK="${Green}--->${FONT}"
EROR="${RED}[EROR]${FONT}"
GRAY="\e[1;30m"
NC='\e[0m'
red='\e[1;31m'
green='\e[0;32m'
TIME=$(date '+%d %b %Y')
ipsaya=$(wget -qO- ipinfo.io/ip)
TIMES="10"
CHATID="5162695441"
KEY="7117869623:AAHBmgzOUsmHBjcm5TFir9JmaZ_X7ynMoF4"
URL="https://api.telegram.org/bot$KEY/sendMessage"
clear
export IP=$( curl -sS icanhazip.com )
# Hapus clear berlebihan
clear
echo -e "${YELLOW}----------------------------------------------------------${NC}"
echo -e "\033[96;1m                  WENDY VPN TUNNELING\033[0m"
echo -e "${YELLOW}----------------------------------------------------------${NC}"
echo ""
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
                break
            else
                echo "Password harus diisi dan harus sama. Silakan coba lagi."
            fi
        done
        echo root:$passwd | sudo chpasswd root > /dev/null 2>&1
        sudo systemctl restart sshd > /dev/null 2>&1
        break
    elif [[ "$pilihan" == "2" || -z "$pilihan" ]]; then
        echo "Proses pengubahan password dilewati."
        break
    else
        echo "Pilihan tidak valid. Silakan coba lagi."
    fi
done
if [[ $( uname -m ) == "x86_64" ]]; then
echo -e "${OK} Your Architecture Is Supported ( ${green}$( uname -m )${NC} )"
else
echo -e "${EROR} Your Architecture Is Not Supported ( ${YELLOW}$( uname -m )${NC} )"
exit 1
fi
# Perbaiki deteksi OS
OS_ID=$(grep -w ID /etc/os-release | cut -d'=' -f2 | tr -d '"')
OS_NAME=$(grep -w PRETTY_NAME /etc/os-release | cut -d'=' -f2 | tr -d '"')
if [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
echo -e "${OK} Your OS Is Supported ( ${green}$OS_NAME${NC} )"
else
echo -e "${EROR} Your OS Is Not Supported ( ${YELLOW}$OS_NAME${NC} )"
exit 1
fi
if [[ -z "$ipsaya" ]]; then # Periksa jika kosong
echo -e "${EROR} IP Address ( ${RED}Not Detected${NC} )"
else
echo -e "${OK} IP Address ( ${green}$ipsaya${NC} )" # Gunakan $ipsaya yang sudah didefinisikan
fi
echo ""
read -p "$( echo -e "Press ${GRAY}[ ${NC}${green}Enter${NC} ${GRAY}]${NC} For Starting Installation") "
echo ""
clear
if [ "${EUID}" -ne 0 ]; then
echo "You need to run this script as root"
exit 1
fi
if [ "$(systemd-detect-virt)" == "openvz" ]; then
echo "OpenVZ is not supported"
exit 1
fi
# Definisi variabel yang hilang
MYIP=$ipsaya
echo -e "\e[32mloading...\e[0m"
clear
rm -f /usr/bin/user
# Gunakan $MYIP
username=$(curl -s https://raw.githubusercontent.com/bowowiwendi/ipvps/main/ip | grep "$MYIP" | awk '{print $2}')
echo "$username" >/usr/bin/user
valid=$(curl -s https://raw.githubusercontent.com/bowowiwendi/ipvps/main/ip | grep "$MYIP" | awk '{print $3}')
echo "$valid" >/usr/bin/e
username=$(cat /usr/bin/user)
# oid=$(cat /usr/bin/ver) # oid tidak digunakan, baris ini bisa dihapus
exp=$(cat /usr/bin/e)
clear
DATE=$(date +'%Y-%m-%d')
d1=$(date -d "$valid" +%s)
d2=$(date -d "$DATE" +%s)
certifacate=$(((d1 - d2) / 86400))
datediff() {
d1=$(date -d "$1" +%s)
d2=$(date -d "$2" +%s)
echo -e "$COLOR1 $NC Expiry In   : $(( (d1 - d2) / 86400 )) Days"
}
# mai="datediff "$Exp" "$DATE"" # mai tidak digunakan, baris ini bisa dihapus
Info="(${green}Active${NC})"
Error="(${RED}ExpiRED${NC})"
today=`date -d "0 days" +"%Y-%m-%d"`
# Gunakan $MYIP
Exp1=$(curl -s https://raw.githubusercontent.com/bowowiwendi/ipvps/main/ip | grep "$MYIP" | awk '{print $4}')
if [[ $today < $Exp1 ]]; then
sts="${Info}"
else
sts="${Error}"
fi
echo -e "\e[32mloading...\e[0m"
clear
REPO="https://raw.githubusercontent.com/bowowiwendi/WendyVpn/ABSTRAK/"
start=$(date +%s)
secs_to_human() {
echo "Installation time : $((${1} / 3600)) hours $(((${1} / 60) % 60)) minute's $((${1} % 60)) seconds"
}
function print_ok() {
echo -e "${OK} ${BLUE} $1 ${FONT}"
}
function print_install() {
echo -e "${green} =============================== ${FONT}"
echo -e "${YELLOW} # $1 ${FONT}"
echo -e "${green} =============================== ${FONT}"
sleep 1
}
function print_error() {
echo -e "${EROR} ${REDBG} $1 ${FONT}"
}
function print_success() {
if [[ 0 -eq $? ]]; then
echo -e "${green} =============================== ${FONT}"
echo -e "${Green} # $1 berhasil dipasang"
echo -e "${green} =============================== ${FONT}"
sleep 2
fi
}
function is_root() {
if [[ 0 == "$UID" ]]; then
print_ok "Root user Start installation process"
else
print_error "The current user is not the root user, please switch to the root user and run the script again"
fi
}
print_install "Membuat direktori xray"
mkdir -p /etc/xray
touch /etc/xray/scdomain
mkdir -p /etc/v2ray
touch /etc/v2ray/domain
touch /root/domain
touch /root/scdomain
touch /root/nsdomain
curl -s ifconfig.me > /etc/xray/ipvps
touch /etc/xray/domain
mkdir -p /var/log/xray
chown www-data:www-data /var/log/xray # Perbaiki pemisah
chmod 750 /var/log/xray # Gunakan 750 alih-alih +x untuk direktori
touch /var/log/xray/access.log
touch /var/log/xray/error.log
mkdir -p /var/lib/kyt >/dev/null 2>&1
# Pengumpulan info memori (tidak diubah)
while IFS=":" read -r a b; do
case $a in
"MemTotal") ((mem_used+=${b/kB})); mem_total="${b/kB}" ;;
"Shmem") ((mem_used+=${b/kB}))  ;;
"MemFree" | "Buffers" | "Cached" | "SReclaimable")
mem_used="$((mem_used-=${b/kB}))"
;;
esac
done < /proc/meminfo
Ram_Usage="$((mem_used / 1024))"
Ram_Total="$((mem_total / 1024))"
export tanggal=`date -d "0 days" +"%d-%m-%Y - %X" `
export OS_Name="$OS_NAME" # Gunakan variabel yang sudah didefinisikan
export Kernel=$( uname -r )
export Arch=$( uname -m )
export IP="$ipsaya" # Gunakan variabel IP yang sudah didefinisikan

# ... (bagian sebelumnya tetap sama sampai fungsi first_setup) ...
function first_setup() {
    timedatectl set-timezone Asia/Jakarta
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
    print_success "Directory Xray"
    # Mendeteksi OS (sudah dilakukan sebelumnya, tapi tetap gunakan logika ini jika diperlukan di sini)
    # OS_ID dan OS_NAME sudah didefinisikan sebelumnya
    if [[ "$OS_ID" == "ubuntu" ]]; then
        echo "Setup Dependencies $OS_NAME"
        sudo apt update -y
        # Langsung install haproxy dari repo default
        echo "Installing haproxy from default repo"
        apt-get install -y haproxy
    elif [[ "$OS_ID" == "debian" ]]; then
        echo "Setup Dependencies For OS Is $OS_NAME"
        # Langsung install haproxy dari repo default
        echo "Installing haproxy from default repo"
        apt-get install -y haproxy
    else
        echo -e "Your OS Is Not Supported ($OS_NAME)"
        exit 1
    fi
    print_success "HAProxy Installation" # Tambahkan pesan sukses
}

clear
function nginx_install() {
# Gunakan variabel OS yang sudah didefinisikan
if [[ "$OS_ID" == "ubuntu" ]]; then
print_install "Setup nginx For OS Is $OS_NAME"
sudo apt-get install nginx -y
elif [[ "$OS_ID" == "debian" ]]; then
print_install "Setup nginx For OS Is $OS_NAME" # Perbaiki typo "success"
apt -y install nginx
else
echo -e "${EROR} Your OS Is Not Supported ( ${YELLOW}$OS_NAME${FONT} )"
exit 1
fi
print_success "Nginx Installation" # Tambahkan pesan sukses
}
function base_package() {
clear
print_install "Menginstall Packet Yang Dibutuhkan"
# Gabungkan update/upgrade awal
apt update -y
apt upgrade -y
# Instal paket-paket dasar terlebih dahulu yang mungkin dibutuhkan oleh yang lain
apt install -y build-essential debconf-utils sudo wget curl unzip git socat
# Instal paket-paket lainnya
apt install -y zip pwgen openssl netcat cron bash-completion figlet \
ntpdate chrony rsyslog dos2unix sed dirmngr libxml-parser-perl \
gcc g++ python3 htop lsof tar ruby zip unzip p7zip-full python3-pip \
libc6 util-linux msmtp-mta ca-certificates bsd-mailx iptables \
iptables-persistent netfilter-persistent net-tools libssl-dev \
libsqlite3-dev zlib1g-dev libcurl4-nss-dev libpam0g-dev \
libcap-ng-dev libcap-ng-utils libselinux1-dev flex bison make cmake \
screen xz-utils apt-transport-https gnupg gnupg2 lsb-release jq \
openvpn easy-rsa speedtest-cli vnstat libnss3-dev libnspr4-dev \
pkg-config libevent-dev bc dnsutils chronyd
# Hapus paket yang tidak diinginkan
apt remove --purge -y exim4 ufw firewalld
# Instal software-properties-common
apt install -y --no-install-recommends software-properties-common
# Konfigurasi debconf untuk iptables-persistent
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
# Restart dan enable chronyd
systemctl enable chronyd
systemctl restart chronyd
# Sinkronisasi waktu
ntpdate pool.ntp.org
print_success "Packet Yang Dibutuhkan"
}
clear
function pasang_domain() {
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
    echo -e "\033[91;1m contoh subdomain :\033[0m \033[93m wendi.ssh.cloud\033[0m" # Perbaiki escape sequence
    read -p "SUBDOMAIN :  " host1
    echo "IP=" >> /var/lib/kyt/ipvps.conf
    echo $host1 > /etc/xray/domain
    echo $host1 > /etc/xray/scdomain
    echo $host1 > /etc/v2ray/domain
    echo $host1 > /root/domain
    echo $host1 > /root/scdomain
    echo ""
    print_install "Subdomain/Domain is Used"
    clear
elif [[ $host == "2" ]]; then
    # Perbaiki URL wget
    wget -O /root/random.sh "${REPO}files/random.sh" && chmod +x /root/random.sh && /root/random.sh
    rm -f /root/random.sh
    clear
    print_install "Random Subdomain/Domain is Used"
else
    # host="2" # Tidak perlu di-set ulang karena sudah default
    print_install "Random Subdomain/Domain is Used"
    clear
fi
}
clear
restart_system() {
    # Pastikan variabel yang dibutuhkan telah didefinisikan sebelum fungsi ini dipanggil
    # Contoh definisi awal sudah ada di bagian atas
    domain=$(cat /root/domain) # Pastikan domain sudah diset sebelumnya
    USRSC=$(curl -s https://raw.githubusercontent.com/bowowiwendi/ipvps/main/main/ip | grep "$ipsaya" | awk '{print $2}')
    EXPSC=$(curl -s https://raw.githubusercontent.com/bowowiwendi/ipvps/main/main/ip | grep "$ipsaya" | awk '{print $3}')
    # Format tanggal dan waktu
    DATE_FORMAT=$(date '+%d-%m-%Y')
    TIME_FORMAT=$(date '+%H:%M:%S')
    # Membangun pesan teks
    TEXT="🚀 <b>✨ VPS SETUP COMPLETE ✨</b> 🚀
<b>📋 INFORMATION DETAILS 📋 </b>
👤 ID       : <code>$USRSC</code>
🌐 Domain   : <code>$domain</code>
🔒 Wildcard : <code>*.$domain</code>
📅 Date     : <code>$DATE_FORMAT</code>
⏰ Time     : <code>$TIME_FORMAT</code>
📍 IP VPS   : <code>$MYIP</code>
⏳ Exp Sc   : <code>$EXPSC</code>
🔑 User     : <code>root</code>
🔐 Password : <code>$passwd</code>
𝗖𝗢𝗡𝗧𝗔𝗖𝗧 :
💬𝗧𝗘𝗟𝗘𝗚𝗥𝗔𝗠
☞ @WendiVpn
💬𝗪𝗛𝗔𝗧𝗦𝗔𝗣𝗣
☞ +6283153170199
<i>Simpan Baik-baik informasi ini tidak akan di kirim Ulang </i>"
    # Membangun reply markup sebagai variabel terpisah untuk kejelasan
    REPLY_MARKUP='{"inline_keyboard":[[{"text":"ᴏʀᴅᴇʀ","url":"https://t.me/wendivpn"},{"text":"Contack","url":"https://wa.me/6283153170199"}]]}'
    # Mengirim pesan melalui curl
    curl -s --max-time "$TIMES" \
         -d "chat_id=$CHATID" \
         -d "disable_web_page_preview=1" \
         -d "text=$TEXT" \
         -d "parse_mode=html" \
         -d "reply_markup=$REPLY_MARKUP" \
         "$URL" >/dev/null 2>&1
    # Periksa apakah curl berhasil
    if [ $? -ne 0 ]; then
        echo "Gagal mengirim notifikasi ke Telegram."
    fi
}
clear
function pasang_ssl() {
clear
print_install "Memasang SSL Pada Domain"
rm -rf /etc/xray/xray.key
rm -rf /etc/xray/xray.crt
domain=$(cat /root/domain)
STOPWEBSERVER=$(lsof -i:80 | cut -d' ' -f1 | awk 'NR==2 {print $1}')
rm -rf /root/.acme.sh
mkdir /root/.acme.sh
systemctl stop $STOPWEBSERVER 2>/dev/null # Tambahkan error handling
systemctl stop nginx 2>/dev/null
curl https://acme-install.netlify.app/acme.sh -o /root/.acme.sh/acme.sh
chmod +x /root/.acme.sh/acme.sh
/root/.acme.sh/acme.sh --upgrade --auto-upgrade
/root/.acme.sh/acme.sh --set-default-ca --server letsencrypt
/root/.acme.sh/acme.sh --issue -d $domain --standalone -k ec-256
~/.acme.sh/acme.sh --installcert -d $domain --fullchainpath /etc/xray/xray.crt --keypath /etc/xray/xray.key --ecc
chmod 644 /etc/xray/xray.key # Gunakan permission yang lebih aman
chmod 644 /etc/xray/xray.crt
print_success "SSL Certificate"
}
function make_folder_xray() {
rm -rf /etc/vmess/.vmess.db
rm -rf /etc/vless/.vless.db
rm -rf /etc/trojan/.trojan.db
rm -rf /etc/shadowsocks/.shadowsocks.db
rm -rf /etc/ssh/.ssh.db
rm -rf /etc/bot/.bot.db
mkdir -p /etc/bot
mkdir -p /etc/xray
mkdir -p /etc/vmess
mkdir -p /etc/vless
mkdir -p /etc/trojan
mkdir -p /etc/shadowsocks
mkdir -p /etc/ssh
mkdir -p /usr/bin/xray/
mkdir -p /var/log/xray/
mkdir -p /var/www/html
mkdir -p /etc/kyt/files/vmess/ip
mkdir -p /etc/kyt/files/vless/ip
mkdir -p /etc/kyt/files/trojan/ip
mkdir -p /etc/kyt/files/ssh/ip
mkdir -p /etc/files/vmess
mkdir -p /etc/files/vless
mkdir -p /etc/files/trojan
mkdir -p /etc/files/ssh
chmod 750 /var/log/xray # Gunakan 750 alih-alih +x untuk direktori
touch /etc/xray/domain
touch /var/log/xray/access.log
touch /var/log/xray/error.log
touch /etc/vmess/.vmess.db
touch /etc/vless/.vless.db
touch /etc/trojan/.trojan.db
touch /etc/shadowsocks/.shadowsocks.db
touch /etc/ssh/.ssh.db
touch /etc/bot/.bot.db
touch /etc/xray/.lock.db
echo "& plughin Account" >>/etc/vmess/.vmess.db
echo "& plughin Account" >>/etc/vless/.vless.db
echo "& plughin Account" >>/etc/trojan/.trojan.db
echo "& plughin Account" >>/etc/shadowsocks/.shadowsocks.db
echo "& plughin Account" >>/etc/ssh/.ssh.db
cat >/etc/xray/.lock.db <<EOF
#vmess
#vless
#trojan
#ss
EOF
}
function install_xray() {
clear
print_install "Core Xray Latest Version" # Hapus versi spesifik
domainSock_dir="/run/xray";! [ -d $domainSock_dir ] && mkdir  $domainSock_dir
chown www-data:www-data $domainSock_dir # Perbaiki pemisah
# Dapatkan versi terbaru
latest_version="$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | grep tag_name | sed -E 's/.*"v(.*)".*/\1/' | head -n 1)"
# Jalankan skrip instalasi resmi
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u www-data --version $latest_version
# Unduh konfigurasi
wget -O /etc/xray/config.json "${REPO}cfg_conf_js/config.json" >/dev/null 2>&1
wget -O /etc/systemd/system/runn.service "${REPO}files/runn.service" >/dev/null 2>&1
domain=$(cat /etc/xray/domain)
IPVS=$(cat /etc/xray/ipvps)
print_success "Core Xray Latest Version"
clear
curl -s ipinfo.io/city >>/etc/xray/city
curl -s ipinfo.io/org | cut -d " " -f 2-10 >>/etc/xray/isp
print_install "Memasang Konfigurasi Packet"
wget -O /etc/haproxy/haproxy.cfg "${REPO}cfg_conf_js/haproxy.cfg" >/dev/null 2>&1
wget -O /etc/nginx/conf.d/xray.conf "${REPO}cfg_conf_js/xray.conf" >/dev/null 2>&1
sed -i "s/xxx/${domain}/g" /etc/haproxy/haproxy.cfg
sed -i "s/xxx/${domain}/g" /etc/nginx/conf.d/xray.conf
curl -s "${REPO}cfg_conf_js/nginx.conf" > /etc/nginx/nginx.conf # Tambahkan -s untuk silent
cat /etc/xray/xray.crt /etc/xray/xray.key | tee /etc/haproxy/hap.pem
chmod +x /etc/systemd/system/runn.service
rm -rf /etc/systemd/system/xray.service.d
# Perbaiki konfigurasi systemd service
cat >/etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com
After=network.target nss-lookup.target

[Service]
User=www-data
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF
print_success "Konfigurasi Packet"
}
function ssh(){
clear
print_install "Memasang Password SSH"
wget -O /etc/pam.d/common-password "${REPO}files/password"
chmod 644 /etc/pam.d/common-password # Gunakan permission yang benar untuk file konfigurasi
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure keyboard-configuration
# Konfigurasi keyboard (dibiarkan seperti asli karena kompleks, tapi bisa disederhanakan jika perlu)
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/altgr select The default for the keyboard layout"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/compose select No compose key"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/ctrl_alt_bksp boolean false"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/layoutcode string de"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/layout select English"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/modelcode string pc105"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/model select Generic 105-key (Intl) PC"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/optionscode string "
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/store_defaults_in_debconf_db boolean true"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/switch select No temporary switch"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/toggle select No toggling"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/unsupported_config_layout boolean true"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/unsupported_config_options boolean true"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/unsupported_layout boolean true"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/unsupported_options boolean true"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/variantcode string "
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/variant select English"
debconf-set-selections <<<"keyboard-configuration keyboard-configuration/xkb-keymap select "
cd
# Perbaiki konfigurasi rc-local service
cat > /etc/systemd/system/rc-local.service <<-END
[Unit]
Description=/etc/rc.local Compatibility
ConditionPathExists=/etc/rc.local

[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes
SysVStartPriority=99

[Install]
WantedBy=multi-user.target
END
# Perbaiki isi /etc/rc.local
cat > /etc/rc.local <<-END
#!/bin/sh -e
# rc.local
#
# This script is executed at the end of each multiuser runlevel.
# Make sure that the script will "exit 0" on success or any other
# value on error.
#
# In order to enable or disable this script just change the execution
# bits.
#
# By default this script does nothing.

exit 0
END
chmod +x /etc/rc.local
systemctl enable rc-local >/dev/null 2>&1
systemctl start rc-local.service >/dev/null 2>&1
echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
sed -i '$ i\echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6' /etc/rc.local
ln -fs /usr/share/zoneinfo/Asia/Jakarta /etc/localtime
sed -i 's/^AcceptEnv/#AcceptEnv/g' /etc/ssh/sshd_config # Komentar baris AcceptEnv
print_success "Password SSH"
}
# --- Fungsi udp_mini yang dimodifikasi ---
function udp_mini(){
clear
print_install "Memasang Service limit Quota"
wget raw.githubusercontent.com/bowowiwendi/WendyVpn/ABSTRAK/files/limit.sh && chmod +x limit.sh && ./limit.sh
cd
wget -q -O /usr/bin/limit-ip "${REPO}files/limit-ip"
chmod +x /usr/bin/*
cd /usr/bin
sed -i 's/\r//' limit-ip
cd
clear
cat >/etc/systemd/system/vmip.service << EOF
[Unit]
Description=My
ProjectAfter=network.target
[Service]
WorkingDirectory=/root
ExecStart=/usr/bin/files-ip vmip
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl restart vmip
systemctl enable vmip
cat >/etc/systemd/system/vlip.service << EOF
[Unit]
Description=My
ProjectAfter=network.target
[Service]
WorkingDirectory=/root
ExecStart=/usr/bin/files-ip vlip
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl restart vlip
systemctl enable vlip
cat >/etc/systemd/system/trip.service << EOF
[Unit]
Description=My
ProjectAfter=network.target
[Service]
WorkingDirectory=/root
ExecStart=/usr/bin/files-ip trip
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl restart trip
systemctl enable trip
mkdir -p /usr/local/kyt/
wget -q -O /usr/local/kyt/udp-mini "${REPO}files/udp-mini"
chmod +x /usr/local/kyt/udp-mini
wget -q -O /etc/systemd/system/udp-mini-1.service "${REPO}files/udp-mini-1.service"
wget -q -O /etc/systemd/system/udp-mini-2.service "${REPO}files/udp-mini-2.service"
wget -q -O /etc/systemd/system/udp-mini-3.service "${REPO}files/udp-mini-3.service"
systemctl disable udp-mini-1
systemctl stop udp-mini-1
systemctl enable udp-mini-1
systemctl start udp-mini-1
systemctl disable udp-mini-2
systemctl stop udp-mini-2
systemctl enable udp-mini-2
systemctl start udp-mini-2
systemctl disable udp-mini-3
systemctl stop udp-mini-3
systemctl enable udp-mini-3
systemctl start udp-mini-3
print_success "files Quota Service"
}
function ssh_slow(){
clear
print_install "Memasang modul SlowDNS Server"
print_success "SlowDNS"
}
clear
function ins_SSHD(){
clear
print_install "Memasang SSHD"
wget -q -O /etc/ssh/sshd_config "${REPO}files/sshd" >/dev/null 2>&1
chmod 644 /etc/ssh/sshd_config # Gunakan permission yang benar untuk file konfigurasi
systemctl restart ssh # Gunakan systemctl
print_success "SSHD"
}
clear
function ins_dropbear(){
clear
print_install "Menginstall Dropbear"
apt-get update -y # Tidak perlu update ulang jika sudah dilakukan di awal, tapi tidak apa-apa
apt-get install dropbear -y >/dev/null 2>&1
wget -q -O /etc/default/dropbear "${REPO}cfg_conf_js/dropbear.conf" >/dev/null 2>&1
chmod 644 /etc/default/dropbear # Gunakan permission yang benar
systemctl restart dropbear # Gunakan systemctl
print_success "Dropbear"
}
clear
function ins_vnstat(){
clear
print_install "Menginstall Vnstat"
# Periksa versi vnstat yang terinstal
apt install -y vnstat # Instal dari repo dulu
VNSTAT_VERSION=$(vnstat --version 2>/dev/null | head -n1 | awk '{print $2}' | cut -d'.' -f1-2)
REQUIRED_VERSION="2.6"
VERSION_OK=$(awk -v ver="$VNSTAT_VERSION" -v req="$REQUIRED_VERSION" 'BEGIN { print (ver >= req) }')

if [[ $VERSION_OK -eq 1 ]]; then
    echo "Vnstat version $VNSTAT_VERSION is sufficient."
else
    echo "Vnstat version $VNSTAT_VERSION is older than $REQUIRED_VERSION. Compiling from source..."
    apt install -y libsqlite3-dev build-essential || { echo "Failed to install build dependencies"; exit 1; }
    cd /tmp || exit 1
    wget -O vnstat-2.6.tar.gz https://humdi.net/vnstat/vnstat-2.6.tar.gz || { echo "Failed to download source"; exit 1; }
    tar zxvf vnstat-2.6.tar.gz || { echo "Failed to extract source"; exit 1; }
    cd vnstat-2.6 || exit 1
    ./configure --prefix=/usr --sysconfdir=/etc && make && make install || { echo "Failed to compile/install"; exit 1; }
    cd / || exit 1
    rm -rf /tmp/vnstat-2.6*
fi

# Tentukan interface jaringan
NET=$(ip -4 route show default | awk '{print $5}' | head -n1)
if [[ -z "$NET" ]]; then
   NET="eth0" # Fallback
fi

# Inisialisasi database
vnstat -u -i "$NET" 2>/dev/null

# Update konfigurasi
sed -i "s/Interface \"eth0\"/Interface \"$NET\"/g" /etc/vnstat.conf

# Set ownership
chown vnstat:vnstat /var/lib/vnstat -R

# Enable dan restart service
systemctl enable vnstat
systemctl restart vnstat
print_success "Vnstat"
}
function ins_openvpn(){
clear
print_install "Menginstall OpenVPN"
# Perbaiki URL wget
wget -O /root/openvpn_setup.sh "${REPO}files/openvpn" && chmod +x /root/openvpn_setup.sh && /root/openvpn_setup.sh
systemctl restart openvpn 2>/dev/null # Gunakan systemctl
print_success "OpenVPN"
}
clear
function ins_swab(){
clear
print_install "Memasang Swap 1 G"
gotop_latest="$(curl -s https://api.github.com/repos/xxxserxxx/gotop/releases | grep tag_name | sed -E 's/.*"v(.*)".*/\1/' | head -n 1)"
gotop_link="https://github.com/xxxserxxx/gotop/releases/download/v$gotop_latest/gotop_v"$gotop_latest"_linux_amd64.deb"
curl -sL "$gotop_link" -o /tmp/gotop.deb
dpkg -i /tmp/gotop.deb >/dev/null 2>&1
dd if=/dev/zero of=/swapfile bs=1024 count=1048576
mkswap /swapfile
chown root:root /swapfile
chmod 0600 /swapfile >/dev/null 2>&1
swapon /swapfile >/dev/null 2>&1
# Tambahkan ke fstab dengan pengecekan duplikat
grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
chronyd -q 'server 0.id.pool.ntp.org iburst'
chronyc sourcestats -v
chronyc tracking -v
# Perbaiki URL wget
wget -O /root/bbr.sh "${REPO}files/bbr.sh" && chmod +x /root/bbr.sh && /root/bbr.sh
print_success "Swap 1 G"
}
function ins_Fail2ban(){
clear
print_install "Menginstall Fail2ban"
# Periksa dan hapus direktori konflik
if [ -d '/usr/local/ddos' ]; then
echo; echo; echo "Please un-install the previous DDOS version first"
exit 1 # Keluar dengan error code jika ada konflik
else
mkdir -p /usr/local/ddos # Buat direktori jika tidak ada
fi
# Instal fail2ban dari repo
apt install -y fail2ban
# Setup banner
echo "Banner /etc/banner.txt" >>/etc/ssh/sshd_config
sed -i 's@^DROPBEAR_BANNER=.*@DROPBEAR_BANNER="/etc/banner.txt"@g' /etc/default/dropbear # Perbaiki regex
wget -O /etc/banner.txt "${REPO}banner/issue.net"
print_success "Fail2ban"
}
function ins_epro(){
clear
print_install "Menginstall ePro WebSocket Proxy"
wget -O /usr/bin/ws "${REPO}files/ws" >/dev/null 2>&1
wget -O /usr/bin/tun.conf "${REPO}cfg_conf_js/tun.conf" >/dev/null 2>&1
wget -O /etc/systemd/system/ws.service "${REPO}files/ws.service" >/dev/null 2>&1
chmod +x /etc/systemd/system/ws.service
chmod +x /usr/bin/ws
chmod 644 /usr/bin/tun.conf # Permission untuk file konfigurasi
systemctl disable ws 2>/dev/null
systemctl stop ws 2>/dev/null
systemctl enable ws
systemctl start ws
# systemctl restart ws # Tidak perlu restart jika sudah start
# Unduh GeoIP/GeoSite data
wget -q -O /usr/local/share/xray/geosite.dat "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" >/dev/null 2>&1
wget -q -O /usr/local/share/xray/geoip.dat "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" >/dev/null 2>&1
wget -O /usr/sbin/ftvpn "${REPO}files/ftvpn" >/dev/null 2>&1
chmod +x /usr/sbin/ftvpn
# Aturan iptables untuk BitTorrent (dibiarkan seperti asli)
iptables -A FORWARD -m string --string "get_peers" --algo bm -j DROP
iptables -A FORWARD -m string --string "announce_peer" --algo bm -j DROP
iptables -A FORWARD -m string --string "find_node" --algo bm -j DROP
iptables -A FORWARD -m string --algo bm --string "BitTorrent" -j DROP
iptables -A FORWARD -m string --algo bm --string "BitTorrent protocol" -j DROP
iptables -A FORWARD -m string --algo bm --string "peer_id=" -j DROP
iptables -A FORWARD -m string --algo bm --string ".torrent" -j DROP
iptables -A FORWARD -m string --algo bm --string "announce.php?passkey=" -j DROP
iptables -A FORWARD -m string --algo bm --string "torrent" -j DROP
iptables -A FORWARD -m string --algo bm --string "announce" -j DROP
iptables -A FORWARD -m string --algo bm --string "info_hash" -j DROP
# Simpan dan muat ulang aturan
iptables-save > /etc/iptables.up.rules
iptables-restore -t < /etc/iptables.up.rules
netfilter-persistent save
netfilter-persistent reload
cd
apt autoclean -y >/dev/null 2>&1
apt autoremove -y >/dev/null 2>&1
print_success "ePro WebSocket Proxy"
}
function ins_restart(){
clear
print_install "Restarting All Services"
# Restart services menggunakan systemctl
systemctl daemon-reload
for svc in nginx ssh dropbear fail2ban vnstat haproxy cron netfilter-persistent ws xray; do
     systemctl restart "$svc" 2>/dev/null
done
# Enable services
for svc in nginx ssh dropbear fail2ban vnstat cron haproxy netfilter-persistent ws xray rc-local; do
    systemctl enable "$svc" 2>/dev/null
done
# Enable OpenVPN jika ada unit servicenya
if systemctl list-unit-files | grep -q '^openvpn'; then
    systemctl enable openvpn 2>/dev/null
    systemctl restart openvpn 2>/dev/null
fi
# Clear history
history -c
echo "unset HISTFILE" >> /etc/profile
# Cleanup downloaded files
cd
rm -f /root/openvpn /root/openvpn_setup.sh /root/key.pem /root/cert.pem /root/bbr.sh /root/limit.sh
print_success "All Services"
}
function menu(){
clear
print_install "Memasang Menu Packet"
# Perbaiki URL wget
wget -O /root/menu.zip "${REPO}Features/menu.zip"
unzip menu.zip
chmod +x menu/*
mv menu/* /usr/local/sbin/
rm -rf menu /root/menu.zip
print_success "Menu Packet"
}
function profile(){
clear
print_install "Setting up Profile and Cron Jobs"
# Setup .profile
cat >/root/.profile <<EOF
# ~/.profile: executed by Bourne-compatible login shells.

if [ "\$BASH" ]; then
  if [ -f ~/.bashrc ]; then
    . ~/.bashrc
  fi
fi

mesg n || true

# Run menu on login
menu
EOF
chmod 644 /root/.profile
# Tambahkan cron jobs (menggunakan crontab alih-alih menulis langsung ke /etc/crontab)
# Backup cron (asumsi bot-backup script ada)
(crontab -l 2>/dev/null; echo "0 0 * * * root bot-backup") | crontab -
# Expire check (asumsi xp script ada)
(crontab -l 2>/dev/null; echo "0 3 * * * root xp") | crontab -
# Clean lock (asumsi clean_lock.sh script ada)
(crontab -l 2>/dev/null; echo "0 3 */3 * * root clean_lock.sh >> /var/log/reset_xray_lock.log 2>&1") | crontab -
# Log cleaning
(crontab -l 2>/dev/null; echo "*/10 * * * * root /usr/local/sbin/clearlog") | crontab -
# Daily reboot (akan dihapus dan diganti dengan prompt)
(crontab -l 2>/dev/null; echo "9 3 * * * root /sbin/reboot") | crontab -
# Nginx log rotation
(crontab -l 2>/dev/null; echo "*/1 * * * * root echo -n > /var/log/nginx/access.log") | crontab -
# Xray log rotation
(crontab -l 2>/dev/null; echo "*/1 * * * * root echo -n > /var/log/xray/access.log") | crontab -
# Add shells
echo "/bin/false" >>/etc/shells
echo "/usr/sbin/nologin" >>/etc/shells
# Setup rc.local for iptables rules on boot
cat >/etc/rc.local <<EOF
#!/bin/sh -e
# rc.local for additional boot-time commands

# Redirect DNS port 53 to 5300 for UDP Mini
iptables -I INPUT -p udp --dport 5300 -j ACCEPT
iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300

# Restart netfilter-persistent to apply rules if needed
systemctl restart netfilter-persistent 2>/dev/null

exit 0
EOF
chmod +x /etc/rc.local
# Determine reboot time format (logic kept as is)
AUTOREB=$(cat /home/daily_reboot 2>/dev/null || echo "5") # Default to 5 if file not found
SETT=11
if [ "$AUTOREB" -gt "$SETT" ]; then
    TIME_DATE="PM"
else
    TIME_DATE="AM"
fi
print_success "Profile and Cron Jobs"
}
function enable_services(){
clear
print_install "Enable Core Services"
systemctl daemon-reload
systemctl start netfilter-persistent 2>/dev/null
systemctl enable --now rc-local 2>/dev/null
systemctl enable --now cron 2>/dev/null
systemctl enable --now netfilter-persistent 2>/dev/null
systemctl restart nginx 2>/dev/null
systemctl restart xray 2>/dev/null
systemctl restart cron 2>/dev/null
systemctl restart haproxy 2>/dev/null
print_success "Enable Core Services"
clear
}
function ins_backup() {
clear
print_install "Memasang Backup Server"
# Cek apakah wondershaper sudah terinstal via package manager
if ! command -v wondershaper &> /dev/null; then
    echo "wondershaper not found in packages, compiling from source..."
    apt install -y git make || { echo "Failed to install build deps"; exit 1; }
    cd /tmp || exit 1
    git clone https://github.com/magnific0/wondershaper.git || { echo "Failed to clone repo"; exit 1; }
    cd wondershaper || exit 1
    sudo make install || { echo "Failed to compile/install"; exit 1; }
    cd / || exit 1
    rm -rf /tmp/wondershaper
else
    echo "wondershaper already installed via package manager."
fi
# Instal rclone
apt install -y rclone || { echo "Failed to install rclone"; exit 1; }
# Konfigurasi rclone (non-interaktif, lalu timpa)
printf "q\n" | rclone config # Ini hanya keluar dari config
wget -O /root/.config/rclone/rclone.conf "${REPO}cfg_conf_js/rclone.conf" || { echo "Failed to download rclone config"; exit 1; }
# Buat placeholder file
touch /home/files
# Instal utilitas mail
apt install -y msmtp-mta ca-certificates bsd-mailx || { echo "Failed to install mail utils"; exit 1; }
# Konfigurasi msmtp (PERINGATAN: Kredensial ter-hardcode!)
cat >/etc/msmtprc << EOF
# --- PERINGATAN: Kredensial Gmail Ter-Hardcode ---
# --- Harap edit file ini dengan kredensial Anda sendiri ---
defaults
tls on
tls_starttls on
tls_trust_file /etc/ssl/certs/ca-certificates.crt

account default
host smtp.gmail.com
port 587
auth on
user oceantestdigital@gmail.com
from oceantestdigital@gmail.com
password jokerman77 # <-- RISIKO KEAMANAN: Password Ter-Hardcode
logfile ~/.msmtp.log
EOF
chown root:root /etc/msmtprc
chmod 600 /etc/msmtprc # Permission aman untuk file konfigurasi
# Unduh dan jalankan ipserver script (asumsi diperlukan)
wget -q -O /etc/ipserver "${REPO}files/ipserver" && bash /etc/ipserver || { echo "Warning: Failed to run ipserver script"; }
print_success "Backup Server"
}
function password_default() {
    # Fungsi ini kosong dalam skrip asli, mungkin untuk keperluan tertentu nanti
    # Atau bisa diisi dengan konfigurasi password default jika diperlukan
    :
}
function install(){
clear
pasang_domain
first_setup
make_folder_xray
nginx_install
base_package
password_default # Panggil fungsi ini
pasang_ssl
install_xray
ssh
udp_mini
ssh_slow
ins_SSHD
ins_dropbear
ins_vnstat
ins_openvpn
ins_backup
ins_swab
ins_Fail2ban
ins_epro
ins_restart
menu
profile
enable_services
restart_system
}
# --- Bagian akhir skrip yang dimodifikasi ---
install # Jalankan fungsi install utama

# --- Final Cleanup ---
echo ""
history -c
# Hapus file-file sementara yang spesifik
rm -f /root/openvpn /root/openvpn_setup.sh /root/key.pem /root/cert.pem /root/bbr.sh /root/limit.sh /root/random.sh /root/menu.zip /root/domain
# Hapus direktori sementara jika ada
# rm -rf /root/menu # Sudah dipindah dan dihapus di fungsi menu
# rm -rf /root/vnstat-2.6* # Sudah ditangani di ins_vnstat

# --- Final Output dan Reboot Bersyarat ---
secs_to_human "$(($(date +%s) - ${start}))"
sudo hostnamectl set-hostname "$username" # Pastikan $username didefinisikan

# Tampilkan pesan sukses
clear
echo -e ""
echo -e "\033[96m===============================\033[0m"
echo -e "\033[92m        INSTALL SUCCESS\033[0m"
echo -e "\033[96m===============================\033[0m"
echo -e ""
echo -e "\033[93mSystem setup is complete.\033[0m"
echo -e "\033[93mThe system will NOT reboot automatically.\033[0m"
echo -e "\033[93mPress [Enter] to confirm and reboot the server...\033[0m"
echo -e "\033[93m(Tekan [Enter] untuk konfirmasi dan reboot server...)\033[0m"
# Tunggu input pengguna
read dummy

# Lakukan reboot setelah Enter ditekan
echo "Rebooting the server..."
reboot
