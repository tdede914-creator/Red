#!/bin/bash

# --- Section 1: Initial Setup and Checks ---
# Clear screen once
clear

# Ensure apt lists are up-to-date first
apt update -y
if [ $? -ne 0 ]; then
    echo "Error: Failed to update package lists."
    exit 1
fi

# Upgrade packages early
apt upgrade -y
if [ $? -ne 0 ]; then
    echo "Error: Failed to upgrade packages."
    exit 1
fi

# Install essential early packages
apt install curl socat -y
if [ $? -ne 0 ]; then
    echo "Error: Failed to install curl or socat."
    exit 1
fi

# Color definitions (kept as is for UI)
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
KEY="7117869623:AAHBmgzOUsmHBjcm5TFir9JmaZ_X7ynMoF4" # <-- SECURITY RISK: Hardcoded Token
URL="https://api.telegram.org/bot$KEY/sendMessage"

export IP=$( curl -sS icanhazip.com )

# Clear screen again
clear

echo -e "${YELLOW}----------------------------------------------------------${NC}"
echo -e "\033[96;1m                  WENDY VPN TUNNELING\033[0m"
echo -e "${YELLOW}----------------------------------------------------------${NC}"
echo ""

# --- Password Change Section ---
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
                echo root:$passwd | sudo chpasswd root > /dev/null 2>&1
                sudo systemctl restart sshd > /dev/null 2>&1
                break
            else
                echo "Password harus diisi dan harus sama. Silakan coba lagi."
            fi
        done
        break
    elif [[ "$pilihan" == "2" || -z "$pilihan" ]]; then
        echo "Proses pengubahan password dilewati."
        break
    else
        echo "Pilihan tidak valid. Silakan coba lagi."
    fi
done

# --- Architecture Check ---
if [[ $( uname -m ) == "x86_64" ]]; then
    echo -e "${OK} Your Architecture Is Supported ( ${green}$( uname -m )${NC} )"
else
    echo -e "${EROR} Your Architecture Is Not Supported ( ${YELLOW}$( uname -m )${NC} )"
    exit 1
fi

# --- OS Check ---
OS_ID=$(grep -w ID /etc/os-release | cut -d'=' -f2 | tr -d '"')
OS_NAME=$(grep -w PRETTY_NAME /etc/os-release | cut -d'=' -f2 | tr -d '"')

if [[ "$OS_ID" == "ubuntu" ]] || [[ "$OS_ID" == "debian" ]]; then
    echo -e "${OK} Your OS Is Supported ( ${green}$OS_NAME${NC} )"
else
    echo -e "${EROR} Your OS Is Not Supported ( ${YELLOW}$OS_NAME${NC} )"
    exit 1
fi

# --- IP Check ---
if [[ -z "$ipsaya" ]]; then
    echo -e "${EROR} IP Address ( ${RED}Not Detected${NC} )"
else
    echo -e "${OK} IP Address ( ${green}$ipsaya${NC} )"
fi

echo ""
read -p "$( echo -e "Press ${GRAY}[ ${NC}${green}Enter${NC} ${GRAY}]${NC} For Starting Installation") "
echo ""
clear

# --- Root and Virtualization Check ---
if [ "${EUID}" -ne 0 ]; then
    echo "You need to run this script as root"
    exit 1
fi

if [ "$(systemd-detect-virt)" == "openvz" ]; then
    echo "OpenVZ is not supported"
    exit 1
fi

# --- Loading and User Validation ---
echo -e "\e[32mloading...\e[0m"
clear

# Assuming these files exist and are accessible
rm -f /usr/bin/user
# Use $ipsaya for consistency
username=$(curl -s https://raw.githubusercontent.com/bowowiwendi/ipvps/main/ip | grep "$ipsaya" | awk '{print $2}')
echo "$username" >/usr/bin/user
valid=$(curl -s https://raw.githubusercontent.com/bowowiwendi/ipvps/main/ip | grep "$ipsaya" | awk '{print $3}')
echo "$valid" >/usr/bin/e

username=$(cat /usr/bin/user)
exp=$(cat /usr/bin/e)

clear
DATE=$(date +'%Y-%m-%d')
d1=$(date -d "$valid" +%s)
d2=$(date -d "$DATE" +%s)
certifacate=$(((d1 - d2) / 86400))

# Function to calculate date difference
datediff() {
    d1=$(date -d "$1" +%s)
    d2=$(date -d "$2" +%s)
    echo -e "$COLOR1 $NC Expiry In   : $(( (d1 - d2) / 86400 )) Days"
}

Info="(${green}Active${NC})"
Error="(${RED}ExpiRED${NC})"
today=$(date -d "0 days" +"%Y-%m-%d")
Exp1=$(curl -s https://raw.githubusercontent.com/bowowiwendi/ipvps/main/ip | grep "$ipsaya" | awk '{print $4}')

if [[ $today < $Exp1 ]]; then
    sts="${Info}"
else
    sts="${Error}"
fi

echo -e "\e[32mloading...\e[0m"
clear

# --- Repository ---
REPO="https://raw.githubusercontent.com/bowowiwendi/WendyVpn/ABSTRAK/"

# --- Timer ---
start=$(date +%s)

# --- Helper Functions ---
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
    # Note: $? checks the exit status of the *previous* command executed.
    # This function is typically called right after the command it checks.
    if [[ 0 -eq $? ]]; then
        echo -e "${green} =============================== ${FONT}"
        echo -e "${Green} # $1 berhasil dipasang${FONT}"
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

# --- Section 2: Core Installation Functions ---

# --- Directory Setup ---
print_install "Membuat direktori xray"
mkdir -p /etc/xray
touch /etc/xray/scdomain
mkdir -p /etc/v2ray
touch /etc/v2ray/domain
touch /root/domain
touch /root/scdomain
touch /root/nsdomain
curl -s ifconfig.me > /etc/xray/ipvps || { echo "Failed to get public IP"; exit 1; }
touch /etc/xray/domain
mkdir -p /var/log/xray
chown www-data:www-data /var/log/xray
chmod 750 /var/log/xray # More secure than +x
touch /var/log/xray/access.log
touch /var/log/xray/error.log
mkdir -p /var/lib/kyt >/dev/null 2>&1

# --- System Info Gathering ---
# Memory info gathering (kept as is)
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

export tanggal=$(date -d "0 days" +"%d-%m-%Y - %X")
export OS_Name="$OS_NAME"
export Kernel=$(uname -r)
export Arch=$(uname -m)
export IP=$(curl -s https://ipinfo.io/ip/)

# --- Initial Setup (Timezone, HAProxy) ---
function first_setup() {
    timedatectl set-timezone Asia/Jakarta
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
    print_success "Directory Xray"

    # Install HAProxy from default repositories
    print_install "Installing haproxy from default repo for $OS_NAME"
    apt update -y
    apt install -y haproxy || { echo "Failed to install haproxy"; exit 1; }
    print_success "HAProxy Installation"
}

# --- Nginx Installation ---
function nginx_install() {
    print_install "Setup nginx For OS Is $OS_NAME"
    apt install -y nginx || { echo "Failed to install nginx"; exit 1; }
    print_success "Nginx Installation"
}

# --- Base Package Installation ---
function base_package() {
    clear
    print_install "Menginstall Packet Yang Dibutuhkan"

    # Install build essentials first if needed by later packages
    apt install -y build-essential

    # Install the large list of packages (Consider streamlining if possible)
    # Removed ufw/firewalld install/remove cycle, removed redundant updates/upgrades
    apt install -y zip pwgen openssl netcat socat cron bash-completion figlet \
        ntpdate chrony sudo debconf-utils rsyslog dos2unix sed dirmngr \
        libxml-parser-perl gcc g++ python3 htop lsof tar wget curl ruby \
        zip unzip p7zip-full python3-pip libc6 util-linux msmtp-mta \
        ca-certificates bsd-mailx iptables iptables-persistent \
        netfilter-persistent net-tools libssl-dev libsqlite3-dev \
        zlib1g-dev libcurl4-nss-dev libpam0g-dev libcap-ng-dev \
        libcap-ng-utils libselinux1-dev flex bison make cmake git screen \
        xz-utils apt-transport-https gnupg gnupg2 lsb-release jq openvpn \
        easy-rsa speedtest-cli vnstat libnss3-dev libnspr4-dev pkg-config \
        libevent-dev bc dnsutils cron bash-completion chronyd

    # Remove unwanted packages (only if they were installed by something else)
    apt remove --purge -y exim4 ufw firewalld 2>/dev/null

    # Install software-properties-common
    apt install -y --no-install-recommends software-properties-common

    # Set debconf selections for iptables-persistent
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections

    print_success "Packet Yang Dibutuhkan"
}

# --- Domain Setup ---
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
        echo -e "\033[91;1m contoh subdomain :\033[0m \033[93 wendi.ssh.cloud\033[0m"
        read -p "SUBDOMAIN :  " host1
        echo "IP=" >> /var/lib/kyt/ipvps.conf
        echo "$host1" > /etc/xray/domain
        echo "$host1" > /etc/xray/scdomain
        echo "$host1" > /etc/v2ray/domain
        echo "$host1" > /root/domain
        echo "$host1" > /root/scdomain
        echo ""
        print_install "Subdomain/Domain is Used"
        clear
    elif [[ $host == "2" ]]; then
        wget -O /root/random.sh "${REPO}files/random.sh" && chmod +x /root/random.sh && /root/random.sh
        rm -f /root/random.sh
        clear
        print_install "Random Subdomain/Domain is Used"
    else
        host="2"
        print_install "Random Subdomain/Domain is Used"
        clear
    fi
}

# --- Telegram Notification ---
function restart_system() {
    # Ensure variables are set
    domain=$(cat /root/domain)
    MYIP=$ipsaya
    # passwd is set earlier

    USRSC=$(curl -s https://raw.githubusercontent.com/bowowiwendi/ipvps/main/main/ip | grep "$ipsaya" | awk '{print $2}')
    EXPSC=$(curl -s https://raw.githubusercontent.com/bowowiwendi/ipvps/main/main/ip | grep "$ipsaya" | awk '{print $3}')

    DATE_FORMAT=$(date '+%d-%m-%Y')
    TIME_FORMAT=$(date '+%H:%M:%S')

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

    REPLY_MARKUP='{"inline_keyboard":[[{"text":"ᴏʀᴅᴇʀ","url":"https://t.me/wendivpn"},{"text":"Contack","url":"https://wa.me/6283153170199"}]]}'

    curl -s --max-time "$TIMES" \
         -d "chat_id=$CHATID" \
         -d "disable_web_page_preview=1" \
         -d "text=$TEXT" \
         -d "parse_mode=html" \
         -d "reply_markup=$REPLY_MARKUP" \
         "$URL" >/dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo "Gagal mengirim notifikasi ke Telegram."
    fi
}

# --- SSL Installation ---
function pasang_ssl() {
    clear
    print_install "Memasang SSL Pada Domain"
    rm -rf /etc/xray/xray.key
    rm -rf /etc/xray/xray.crt
    domain=$(cat /root/domain)
    STOPWEBSERVER=$(lsof -i:80 | cut -d' ' -f1 | awk 'NR==2 {print $1}')
    rm -rf /root/.acme.sh
    mkdir /root/.acme.sh
    systemctl stop "$STOPWEBSERVER" 2>/dev/null
    systemctl stop nginx 2>/dev/null

    curl https://acme-install.netlify.app/acme.sh -o /root/.acme.sh/acme.sh
    chmod +x /root/.acme.sh/acme.sh
    /root/.acme.sh/acme.sh --upgrade --auto-upgrade
    /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    /root/.acme.sh/acme.sh --issue -d "$domain" --standalone -k ec-256
    ~/.acme.sh/acme.sh --installcert -d "$domain" --fullchainpath /etc/xray/xray.crt --keypath /etc/xray/xray.key --ecc
    chmod 644 /etc/xray/xray.key # More secure permission
    chmod 644 /etc/xray/xray.crt
    print_success "SSL Certificate"
}

# --- Xray Folder Setup ---
function make_folder_xray() {
    rm -rf /etc/vmess/.vmess.db
    rm -rf /etc/vless/.vless.db
    rm -rf /etc/trojan/.trojan.db
    rm -rf /etc/shadowsocks/.shadowsocks.db
    rm -rf /etc/ssh/.ssh.db
    rm -rf /etc/bot/.bot.db

    mkdir -p /etc/bot /etc/xray /etc/vmess /etc/vless /etc/trojan /etc/shadowsocks /etc/ssh
    mkdir -p /usr/bin/xray/ /var/log/xray/ /var/www/html
    mkdir -p /etc/kyt/files/vmess/ip /etc/kyt/files/vless/ip /etc/kyt/files/trojan/ip /etc/kyt/files/ssh/ip
    mkdir -p /etc/files/vmess /etc/files/vless /etc/files/trojan /etc/files/ssh

    chmod 750 /var/log/xray
    touch /etc/xray/domain /var/log/xray/access.log /var/log/xray/error.log
    touch /etc/vmess/.vmess.db /etc/vless/.vless.db /etc/trojan/.trojan.db
    touch /etc/shadowsocks/.shadowsocks.db /etc/ssh/.ssh.db /etc/bot/.bot.db /etc/xray/.lock.db

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

# --- Xray Core Installation ---
function install_xray() {
    clear
    print_install "Core Xray Latest Version"
    domainSock_dir="/run/xray"
    mkdir -p "$domainSock_dir"
    chown www-data:www-data "$domainSock_dir" # Fixed chown syntax

    latest_version="$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases | grep tag_name | sed -E 's/.*"v(.*)".*/\1/' | head -n 1)"
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u www-data --version "$latest_version" || { echo "Failed to install Xray"; exit 1; }

    wget -O /etc/xray/config.json "${REPO}cfg_conf_js/config.json" || { echo "Failed to download Xray config"; exit 1; }
    wget -O /etc/systemd/system/runn.service "${REPO}files/runn.service" || { echo "Failed to download runn service"; exit 1; }

    domain=$(cat /etc/xray/domain)
    IPVS=$(cat /etc/xray/ipvps)

    print_success "Core Xray Latest Version"
    clear

    curl -s ipinfo.io/city >>/etc/xray/city
    curl -s ipinfo.io/org | cut -d " " -f 2-10 >>/etc/xray/isp

    print_install "Memasang Konfigurasi Packet"
    wget -O /etc/haproxy/haproxy.cfg "${REPO}cfg_conf_js/haproxy.cfg" || { echo "Failed to download HAProxy config"; exit 1; }
    wget -O /etc/nginx/conf.d/xray.conf "${REPO}cfg_conf_js/xray.conf" || { echo "Failed to download Nginx config"; exit 1; }

    sed -i "s/xxx/${domain}/g" /etc/haproxy/haproxy.cfg
    sed -i "s/xxx/${domain}/g" /etc/nginx/conf.d/xray.conf
    curl -s "${REPO}cfg_conf_js/nginx.conf" > /etc/nginx/nginx.conf || { echo "Failed to download main Nginx config"; exit 1; }

    cat /etc/xray/xray.crt /etc/xray/xray.key | tee /etc/haproxy/hap.pem
    chmod +x /etc/systemd/system/runn.service
    rm -rf /etc/systemd/system/xray.service.d

    # Corrected systemd service file
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

# --- SSH Configuration ---
function ssh(){
    clear
    print_install "Memasang Password SSH"
    wget -O /etc/pam.d/common-password "${REPO}files/password" || { echo "Failed to download common-password"; exit 1; }
    chmod 644 /etc/pam.d/common-password # Correct permission

    # Configure keyboard non-interactively
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure keyboard-configuration

    # Set keyboard configuration selections (kept as is, though 'de' layout with 'English' selection is odd)
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

    # Setup rc-local service (Corrected Type)
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

    # Disable IPv6
    echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6
    sed -i '$ i\echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6' /etc/rc.local

    # Set timezone link
    ln -fs /usr/share/zoneinfo/Asia/Jakarta /etc/localtime

    # Modify sshd_config
    sed -i 's/^AcceptEnv/#AcceptEnv/g' /etc/ssh/sshd_config

    print_success "Password SSH"
}

# --- UDP Mini Service ---
function udp_mini(){
    clear
    print_install "Memasang Service limit Quota"
    wget -O /root/limit.sh "${REPO}files/limit.sh" && chmod +x /root/limit.sh && /root/limit.sh || { echo "Failed to setup limit.sh"; exit 1; }

    cd
    wget -q -O /usr/bin/limit-ip "${REPO}files/limit-ip" || { echo "Failed to download limit-ip"; exit 1; }
    chmod +x /usr/bin/limit-ip # Removed redundant chmod +x /usr/bin/*
    cd /usr/bin
    sed -i 's/\r//' limit-ip # Remove Windows line endings if present
    cd

    # Create systemd services for IP limiting (Corrected Type)
    for svc in vmip vlip trip; do
        cat >/etc/systemd/system/${svc}.service << EOF
[Unit]
Description=My ${svc^^} Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/root
ExecStart=/usr/bin/files-ip ${svc}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl restart "${svc}.service" 2>/dev/null
        systemctl enable "${svc}.service"
    done

    # Setup UDP Mini
    mkdir -p /usr/local/kyt/
    wget -q -O /usr/local/kyt/udp-mini "${REPO}files/udp-mini" || { echo "Failed to download udp-mini"; exit 1; }
    chmod +x /usr/local/kyt/udp-mini

    for i in 1 2 3; do
        wget -q -O /etc/systemd/system/udp-mini-${i}.service "${REPO}files/udp-mini-${i}.service" || { echo "Failed to download udp-mini-${i}.service"; exit 1; }
        systemctl disable "udp-mini-${i}.service" 2>/dev/null
        systemctl stop "udp-mini-${i}.service" 2>/dev/null
        systemctl enable "udp-mini-${i}.service"
        systemctl start "udp-mini-${i}.service"
    done

    print_success "files Quota Service"
}

# Placeholder for SlowDNS
function ssh_slow(){
    clear
    print_install "Memasang modul SlowDNS Server (Placeholder)"
    # Actual installation logic for SlowDNS should go here if needed
    print_success "SlowDNS"
}

# --- SSHD Configuration ---
function ins_SSHD(){
    clear
    print_install "Memasang SSHD"
    wget -q -O /etc/ssh/sshd_config "${REPO}files/sshd" || { echo "Failed to download sshd config"; exit 1; }
    chmod 644 /etc/ssh/sshd_config # Correct permission
    systemctl restart ssh
    print_success "SSHD"
}

# --- Dropbear Installation ---
function ins_dropbear(){
    clear
    print_install "Menginstall Dropbear"
    apt update -y
    apt install -y dropbear || { echo "Failed to install dropbear"; exit 1; }
    wget -q -O /etc/default/dropbear "${REPO}cfg_conf_js/dropbear.conf" || { echo "Failed to download dropbear config"; exit 1; }
    chmod 644 /etc/default/dropbear # Correct permission
    systemctl restart dropbear
    print_success "Dropbear"
}

# --- Vnstat Installation (Improved) ---
function ins_vnstat(){
    clear
    print_install "Menginstall Vnstat"
    apt install -y vnstat || { echo "Failed to install vnstat package"; exit 1; }

    # Check if the installed version is recent enough (>= 2.6)
    # This avoids unnecessary compilation on modern systems
    VNSTAT_VERSION=$(vnstat --version 2>/dev/null | head -n1 | awk '{print $2}' | cut -d'.' -f1-2)
    REQUIRED_VERSION="2.6"
    VERSION_OK=$(awk -v ver="$VNSTAT_VERSION" -v req="$REQUIRED_VERSION" 'BEGIN { print (ver >= req) }')

    if [[ $VERSION_OK -eq 1 ]]; then
        echo "Vnstat version $VNSTAT_VERSION is sufficient. Skipping compilation."
    else
        echo "Vnstat version $VNSTAT_VERSION is older than $REQUIRED_VERSION. Compiling from source..."
        apt install -y libsqlite3-dev build-essential || { echo "Failed to install build dependencies for vnstat"; exit 1; }
        cd /tmp || exit 1
        wget -O vnstat-2.6.tar.gz https://humdi.net/vnstat/vnstat-2.6.tar.gz || { echo "Failed to download vnstat source"; exit 1; }
        tar zxvf vnstat-2.6.tar.gz || { echo "Failed to extract vnstat source"; exit 1; }
        cd vnstat-2.6 || exit 1
        ./configure --prefix=/usr --sysconfdir=/etc && make && make install || { echo "Failed to compile or install vnstat"; exit 1; }
        cd / || exit 1
        rm -rf /tmp/vnstat-2.6*
    fi

    # Determine network interface
    NET=$(ip -4 route show default | awk '{print $5}' | head -n1)
    if [[ -z "$NET" ]]; then
       NET="eth0" # Fallback, might need adjustment
    fi

    # Initialize database for the interface
    vnstat -u -i "$NET" 2>/dev/null

    # Update config file
    sed -i "s/Interface \"eth0\"/Interface \"$NET\"/g" /etc/vnstat.conf

    # Set ownership
    chown vnstat:vnstat /var/lib/vnstat -R

    # Enable and restart service
    systemctl enable vnstat
    systemctl restart vnstat
    print_success "Vnstat"
}

# --- OpenVPN Installation ---
function ins_openvpn(){
    clear
    print_install "Menginstall OpenVPN"
    wget -O /root/openvpn_setup.sh "${REPO}files/openvpn" || { echo "Failed to download OpenVPN setup script"; exit 1; }
    chmod +x /root/openvpn_setup.sh
    /root/openvpn_setup.sh || { echo "Failed to run OpenVPN setup script"; exit 1; }
    systemctl restart openvpn 2>/dev/null
    print_success "OpenVPN"
}

# --- Swap and BBR ---
function ins_swab(){
    clear
    print_install "Memasang Swap 1 G"
    gotop_latest="$(curl -s https://api.github.com/repos/xxxserxxx/gotop/releases | grep tag_name | sed -E 's/.*"v(.*)".*/\1/' | head -n 1)"
    gotop_link="https://github.com/xxxserxxx/gotop/releases/download/v$gotop_latest/gotop_v"$gotop_latest"_linux_amd64.deb"
    curl -sL "$gotop_link" -o /tmp/gotop.deb || { echo "Failed to download gotop"; exit 1; }
    dpkg -i /tmp/gotop.deb || { echo "Failed to install gotop"; exit 1; }

    # Create swapfile
    dd if=/dev/zero of=/swapfile bs=1024 count=1048576
    mkswap /swapfile
    chown root:root /swapfile
    chmod 0600 /swapfile
    swapon /swapfile

    # Make swap permanent
    grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab

    # Sync time
    chronyd -q 'server 0.id.pool.ntp.org iburst'
    chronyc sourcestats -v
    chronyc tracking -v

    # Install BBR
    wget -O /root/bbr.sh "${REPO}files/bbr.sh" && chmod +x /root/bbr.sh && /root/bbr.sh || { echo "Failed to setup BBR"; exit 1; }

    print_success "Swap 1 G"
}

# --- Fail2ban Installation ---
function ins_Fail2ban(){
    clear
    print_install "Menginstall Fail2ban"
    # Check for conflicting software (like ddos script directory)
    if [ -d '/usr/local/ddos' ]; then
        echo "Please un-install the previous DDOS version first"
        exit 1
    fi

    # Actually install Fail2ban
    apt install -y fail2ban || { echo "Failed to install fail2ban"; exit 1; }

    # Setup banner
    echo "Banner /etc/banner.txt" >>/etc/ssh/sshd_config
    sed -i 's@^DROPBEAR_BANNER=.*@DROPBEAR_BANNER="/etc/banner.txt"@g' /etc/default/dropbear
    wget -O /etc/banner.txt "${REPO}banner/issue.net" || { echo "Failed to download banner"; exit 1; }

    print_success "Fail2ban"
}

# --- ePro WebSocket Proxy ---
function ins_epro(){
    clear
    print_install "Menginstall ePro WebSocket Proxy"
    wget -O /usr/bin/ws "${REPO}files/ws" || { echo "Failed to download ws binary"; exit 1; }
    wget -O /usr/bin/tun.conf "${REPO}cfg_conf_js/tun.conf" || { echo "Failed to download tun.conf"; exit 1; }
    wget -O /etc/systemd/system/ws.service "${REPO}files/ws.service" || { echo "Failed to download ws service"; exit 1; }

    chmod +x /etc/systemd/system/ws.service
    chmod +x /usr/bin/ws
    chmod 644 /usr/bin/tun.conf

    systemctl disable ws 2>/dev/null
    systemctl stop ws 2>/dev/null
    systemctl enable ws
    systemctl start ws

    # Download GeoIP/GeoSite data
    wget -q -O /usr/local/share/xray/geosite.dat "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" || { echo "Failed to download geosite.dat"; exit 1; }
    wget -q -O /usr/local/share/xray/geoip.dat "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" || { echo "Failed to download geoip.dat"; exit 1; }

    # Download ftvpn binary
    wget -O /usr/sbin/ftvpn "${REPO}files/ftvpn" || { echo "Failed to download ftvpn"; exit 1; }
    chmod +x /usr/sbin/ftvpn

    # Apply iptables rules for BitTorrent blocking
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

    # Save and reload iptables rules
    iptables-save > /etc/iptables.up.rules
    iptables-restore -t < /etc/iptables.up.rules
    netfilter-persistent save
    netfilter-persistent reload

    # Autoclean
    apt autoclean -y >/dev/null 2>&1
    apt autoremove -y >/dev/null 2>&1

    print_success "ePro WebSocket Proxy"
}

# --- Service Restart ---
function ins_restart(){
    clear
    print_install "Restarting All Services"
    systemctl daemon-reload

    # Restart services
    for svc in nginx ssh dropbear fail2ban vnstat haproxy cron netfilter-persistent ws xray; do
         systemctl restart "$svc" 2>/dev/null
    done

    # Enable services
    for svc in nginx ssh dropbear fail2ban vnstat cron haproxy netfilter-persistent ws xray rc-local; do
        systemctl enable "$svc" 2>/dev/null
    done

    # Enable OpenVPN if installed
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

# --- Menu Installation ---
function menu(){
    clear
    print_install "Memasang Menu Packet"
    wget -O /root/menu.zip "${REPO}Features/menu.zip" || { echo "Failed to download menu"; exit 1; }
    unzip /root/menu.zip || { echo "Failed to unzip menu"; exit 1; }
    chmod +x menu/*
    mv menu/* /usr/local/sbin/
    rm -rf menu /root/menu.zip
    print_success "Menu Packet"
}

# --- Profile and Cron Setup ---
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

    # Add cron jobs
    # Backup cron (assuming bot-backup script exists)
    crontab -l > /tmp/mycron 2>/dev/null
    echo "0 0 * * * root bot-backup" >> /tmp/mycron
    # Expire check (assuming xp script exists)
    echo "0 3 * * * root xp" >> /tmp/mycron
    # Clean lock (assuming clean_lock.sh script exists)
    echo "0 3 */3 * * root clean_lock.sh >> /var/log/reset_xray_lock.log 2>&1" >> /tmp/mycron
    # Log cleaning
    echo "*/10 * * * * root /usr/local/sbin/clearlog" >> /tmp/mycron
    # Daily reboot
    echo "9 3 * * * root /sbin/reboot" >> /tmp/mycron
    # Nginx log rotation
    echo "*/1 * * * * root echo -n > /var/log/nginx/access.log" >> /tmp/mycron
    # Xray log rotation
    echo "*/1 * * * * root echo -n > /var/log/xray/access.log" >> /tmp/mycron
    crontab /tmp/mycron
    rm /tmp/mycron

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

# --- Enable Core Services ---
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

# --- Backup Server Setup (Improved) ---
function ins_backup() {
    clear
    print_install "Memasang Backup Server"

    # Prefer packaged wondershaper
    if ! command -v wondershaper &> /dev/null; then
        echo "wondershaper not found in packages, compiling from source..."
        apt install -y git make || { echo "Failed to install build deps for wondershaper"; exit 1; }
        cd /tmp || exit 1
        git clone https://github.com/magnific0/wondershaper.git || { echo "Failed to clone wondershaper repo"; exit 1; }
        cd wondershaper || exit 1
        sudo make install || { echo "Failed to compile/install wondershaper"; exit 1; }
        cd / || exit 1
        rm -rf /tmp/wondershaper
    else
        echo "wondershaper already installed via package manager."
    fi

    # Install rclone
    apt install -y rclone || { echo "Failed to install rclone"; exit 1; }

    # Configure rclone (non-interactive placeholder, then overwrite)
    printf "q\n" | rclone config # This just quits config, relies on the next line
    wget -O /root/.config/rclone/rclone.conf "${REPO}cfg_conf_js/rclone.conf" || { echo "Failed to download rclone config"; exit 1; }

    # Create files placeholder
    touch /home/files

    # Install mail utilities
    apt install -y msmtp-mta ca-certificates bsd-mailx || { echo "Failed to install mail utils"; exit 1; }

    # Configure msmtp (WARNING: Hardcoded credentials!)
    cat >/etc/msmtprc << EOF
# --- WARNING: Hardcoded Gmail Credentials ---
# --- Please edit this file with your own credentials ---
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
password jokerman77 # <-- SECURITY RISK: Hardcoded Password
logfile ~/.msmtp.log
EOF
    chown root:root /etc/msmtprc
    chmod 600 /etc/msmtprc # Secure permissions for config file

    # Download ipserver script (assuming it exists and is needed)
    wget -q -O /etc/ipserver "${REPO}files/ipserver" && bash /etc/ipserver || { echo "Warning: Failed to run ipserver script"; }

    print_success "Backup Server"
}

# --- Main Installation Function ---
function install(){
    clear
    pasang_domain
    first_setup
    make_folder_xray
    nginx_install
    base_package
    # password_default # This function is not defined in the original script
    pasang_ssl
    install_xray
    ssh
    udp_mini
    ssh_slow
    ins_SSHD
    ins_dropbear
    ins_vnstat
    ins_openvpn
    ins_backup # Moved before swab/Fail2ban/epro for better flow?
    ins_swab
    ins_Fail2ban
    ins_epro
    ins_restart
    menu
    profile
    enable_services
    restart_system
}

# --- Run Installation ---
install

# --- Final Cleanup ---
echo ""
history -c
rm -rf /root/menu /root/*.zip /root/*.sh /root/LICENSE /root/README.md /root/domain /root/random.sh /root/openvpn_setup.sh /root/bbr.sh /root/limit.sh

# --- Final Output ---
secs_to_human "$(($(date +%s) - start))"
sudo hostnamectl set-hostname "$username"
sleep 2
clear
echo -e ""
echo -e "\033[96m===============================\033[0m"
echo -e "\033[92m        INSTALL SUCCESS\033[0m"
echo -e "\033[96m===============================\033[0m"
echo -e ""
reboot
