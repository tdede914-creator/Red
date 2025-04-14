#!/bin/bash
clear
echo -e "\033[96m===============================\033[0m"
echo -e "\033[92m        UNINSTALL WENDY VPN\033[0m"
echo -e "\033[96m===============================\033[0m"
echo -e ""

# Fungsi untuk menghapus service
remove_services() {
    echo "Menghentikan dan menonaktifkan layanan..."
    systemctl stop xray nginx haproxy dropbear openvpn fail2ban udp-mini-1 udp-mini-2 udp-mini-3 ws vmip vlip trip rc-local
    systemctl disable xray nginx haproxy dropbear openvpn fail2ban udp-mini-1 udp-mini-2 udp-mini-3 ws vmip vlip trip rc-local
    systemctl daemon-reload
}

# Hapus semua paket yang diinstal untuk VPN
remove_packages() {
    echo "Menghapus paket yang diinstal..."
    apt purge -y nginx haproxy dropbear openvpn fail2ban vnstat rclone msmtp-mta \
    chrony wondershaper iptables-persistent netfilter-persistent \
    php-fpm php-common php-cli php-mysql php-gd php-xml php-curl php-zip php-mbstring \
    python3-pip libsqlite3-dev socat bash-completion software-properties-common \
    unzip zip apt-transport-https gnupg2 lsb-release debian-archive-keyring \
    figlet ruby -y
    
    # Hapus semua dependensi yang tidak diperlukan
    apt autoremove --purge -y
    apt clean
}

# Hapus file konfigurasi dan sertifikat
remove_config_files() {
    echo "Menghapus file konfigurasi dan sertifikat..."
    # Direktori
    rm -rf /usr/bin/kyt
    rm -rf /etc/xray
    rm -rf /etc/v2ray
    rm -rf /etc/nginx
    rm -rf /etc/haproxy
    rm -rf /etc/openvpn
    rm -rf /etc/fail2ban
    rm -rf /etc/vnstat
    rm -rf /usr/local/kyt
    rm -rf /root/.acme.sh  # Sertifikat VPN dihapus
    rm -rf /root/.config/rclone
    rm -rf /var/lib/kyt
    rm -rf /var/log/xray
    rm -rf /usr/local/share/xray
    
    # File
    rm -f /etc/rc.local
    rm -f /root/domain
    rm -f /root/scdomain
    rm -f /root/nsdomain
    rm -f /etc/msmtprc
    rm -f /usr/bin/ws
    rm -f /usr/bin/limit-ip
    rm -f /etc/systemd/system/ws.service
    rm -f /etc/systemd/system/udp-mini-*.service
    rm -f /etc/cron.d/daily_reboot
    rm -f /etc/cron.d/logclean
    rm -f /home/daily_reboot
    rm -f /swapfile
    rm -f /usr/local/sbin/menu
    rm -f /usr/local/sbin/xp
    rm -f /usr/local/sbin/bot-backup
}

# Hapus swap file
remove_swap() {
    echo "Menghapus swap file..."
    swapoff /swapfile
    sed -i '/\/swapfile/d' /etc/fstab
    rm -f /swapfile
}

# Hapus cron jobs
remove_cron() {
    echo "Membersihkan cron jobs..."
    crontab -r  # Hapus semua cron jobs
    systemctl restart cron
}

# Reset iptables
reset_firewall() {
    echo "Mereset firewall..."
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    ip6tables -F
    ip6tables -X
    ip6tables -t nat -F
    ip6tables -t nat -X
    ip6tables -t mangle -F
    ip6tables -t mangle -X
    ip6tables -P INPUT ACCEPT
    ip6tables -P FORWARD ACCEPT
    ip6tables -P OUTPUT ACCEPT
    netfilter-persistent save
}

# Hapus pengguna dan grup tambahan
cleanup_users() {
    echo "Menghapus pengguna dan grup tambahan..."
    # Daftar pengguna default Ubuntu (misalnya, root, ubuntu)
    DEFAULT_USERS="root ubuntu"
    
    # Hapus pengguna non-default
    for user in $(awk -F: '{print $1}' /etc/passwd); do
        if ! echo "$DEFAULT_USERS" | grep -qw "$user"; then
            userdel -r "$user" 2>/dev/null
        fi
    done
    
    # Hapus grup non-default
    DEFAULT_GROUPS="root adm sudo ubuntu"
    for group in $(awk -F: '{print $1}' /etc/group); do
        if ! echo "$DEFAULT_GROUPS" | grep -qw "$group"; then
            groupdel "$group" 2>/dev/null
        fi
    done
}

# Kembalikan konfigurasi sistem ke default
reset_system_config() {
    echo "Mengembalikan konfigurasi sistem..."
    
    # Kembalikan /etc/ssh/sshd_config ke default
    if [ -f /etc/ssh/sshd_config ]; then
        apt install --reinstall openssh-server -y
        systemctl restart sshd
    fi
    
    # Kembalikan /etc/sysctl.conf ke default
    if [ -f /etc/sysctl.conf ]; then
        mv /etc/sysctl.conf /etc/sysctl.conf.bak
        echo "# Default sysctl settings" > /etc/sysctl.conf
        sysctl -p
    fi
    
    # Kembalikan pengaturan jaringan ke DHCP (Netplan)
    if [ -d /etc/netplan ]; then
        cat > /etc/netplan/01-netcfg.yaml << EOF
network:
  version: 2
  ethernets:
    all:
      dhcp4: true
EOF
        netplan apply
    fi
    
    # Atur DNS ke default yang andal
    if [ -f /etc/resolv.conf ]; then
        echo "nameserver 8.8.8.8" > /etc/resolv.conf
        echo "nameserver 8.8.4.4" >> /etc/resolv.conf
    fi
    
    # Kembalikan file hosts ke default
    if [ -f /etc/hosts ]; then
        cat > /etc/hosts << EOF
127.0.0.1 localhost
::1       localhost ip6-localhost ip6-loopback
ff02::1   ip6-allnodes
ff02::2   ip6-allrouters
EOF
    fi
}

# Cari dan hapus file sisa
clean_residual_files() {
    echo "Membersihkan file sisa..."
    find / -type f -name "*xray*" -delete 2>/dev/null
    find / -type f -name "*v2ray*" -delete 2>/dev/null
    find / -type f -name "*vpn*" -delete 2>/dev/null
    find / -type f -name "*kyt*" -delete 2>/dev/null
    find / -type d -name "*xray*" -exec rm -rf {} + 2>/dev/null
    find / -type d -name "*v2ray*" -exec rm -rf {} + 2>/dev/null
    find / -type d -name "*vpn*" -exec rm -rf {} + 2>/dev/null
    find / -type d -name "*kyt*" -exec rm -rf {} + 2>/dev/null
}

# Instal ulang paket inti Ubuntu dan perbaiki sertifikat
install_ubuntu_defaults() {
    echo "Menginstal ulang paket inti Ubuntu..."
    apt update
    apt install -y \
        ubuntu-minimal \
        ubuntu-standard \
        openssh-server \
        net-tools \
        curl \
        wget \
        nano \
        vim-tiny \
        less \
        man-db \
        iputils-ping \
        traceroute \
        dnsutils \
        systemd \
        cron \
        logrotate \
        bsdutils \
        ca-certificates \
        bash-completion \
        tzdata \
        locales \
        kbd \
        console-setup
    
    # Perbaiki dan perbarui sertifikat CA
    echo "Memperbaiki konfigurasi sertifikat CA..."
    apt install --reinstall ca-certificates -y
    update-ca-certificates
    
    # Konfigurasi ulang timezone dan locale ke default (contoh: UTC dan en_US.UTF-8)
    echo "Mengatur timezone dan locale..."
    ln -fs /usr/share/zoneinfo/UTC /etc/localtime
    dpkg-reconfigure -f noninteractive tzdata
    locale-gen en_US.UTF-8
    update-locale LANG=en_US.UTF-8
    
    # Pastikan cron berjalan
    systemctl enable cron
    systemctl start cron
}

# Main uninstall process
echo -e "\033[93m[1/9] Menghentikan dan menghapus services...\033[0m"
remove_services

echo -e "\033[93m[2/9] Menghapus paket yang terinstal...\033[0m"
remove_packages

echo -e "\033[93m[3/9] Menghapus file konfigurasi...\033[0m"
remove_config_files

echo -e "\033[93m[4/9] Membersihkan cron jobs...\033[0m"
remove_cron

echo -e "\033[93m[5/9] Menghapus swap file...\033[0m"
remove_swap

echo -e "\033[93m[6/9] Mereset firewall...\033[0m"
reset_firewall

echo -e "\033[93m[7/9] Menghapus pengguna dan grup tambahan...\033[0m"
cleanup_users

echo -e "\033[93m[8/9] Mengembalikan konfigurasi sistem...\033[0m"
reset_system_config

echo -e "\033[93m[9/9] Menginstal ulang paket inti Ubuntu...\033[0m"
install_ubuntu_defaults

echo -e "\033[93mMembersihkan file sisa...\033[0m"
clean_residual_files

echo -e "\033[92mUninstall selesai! System akan reboot dalam 5 detik...\033[0m"
sleep 5
reboot