#!/bin/bash
clear
echo -e "\033[96m===============================\033[0m"
echo -e "\033[92m        UNINSTALL WENDY VPN\033[0m"
echo -e "\033[96m===============================\033[0m"
echo -e ""

# Fungsi untuk menghapus service
remove_services() {
    systemctl stop xray nginx haproxy dropbear openvpn fail2ban udp-mini-1 udp-mini-2 udp-mini-3 ws vmip vlip trip rc-local
    systemctl disable xray nginx haproxy dropbear openvpn fail2ban udp-mini-1 udp-mini-2 udp-mini-3 ws vmip vlip trip rc-local
    systemctl daemon-reload
}

# Hapus package yang diinstal
remove_packages() {
    apt purge -y nginx haproxy dropbear openvpn fail2ban vnstat rclone msmtp-mta \
    chrony wondershaper iptables-persistent netfilter-persistent \
    php-fpm php-common php-cli php-mysql php-gd php-xml php-curl php-zip php-mbstring \
    python3-pip libsqlite3-dev socat cron bash-completion software-properties-common \
    unzip zip apt-transport-https gnupg2 ca-certificates lsb-release debian-archive-keyring \
    figlet ruby -y
    
    apt autoremove -y
    apt clean
}

# Hapus file konfigurasi
remove_config_files() {
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
    rm -rf /root/.acme.sh
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
    swapoff /swapfile
    sed -i '/\/swapfile/d' /etc/fstab
    rm -f /swapfile
}

# Hapus cron jobs
remove_cron() {
    crontab -l | grep -v 'bot-backup' | crontab -
    crontab -l | grep -v 'xp' | crontab -
    crontab -l | grep -v 'clearlog' | crontab -
    systemctl restart cron
}

# Reset iptables
reset_firewall() {
    iptables -F
    iptables -X
    iptables -t nat -F
    iptables -t nat -X
    iptables -t mangle -F
    iptables -t mangle -X
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    netfilter-persistent save
}

# Hapus user dan file terkait
# cleanup_users() {
#     passwd -l root
#     deluser --remove-home www-data
#     userdel -r vnstat
# }

# Main uninstall process
echo -e "\033[93m[1/6] Menghentikan dan menghapus services...\033[0m"
remove_services

echo -e "\033[93m[2/6] Menghapus paket yang terinstal...\033[0m"
remove_packages

echo -e "\033[93m[3/6] Menghapus file konfigurasi...\033[0m"
remove_config_files

echo -e "\033[93m[4/6] Membersihkan cron jobs...\033[0m"
remove_cron

echo -e "\033[93m[5/6] Menghapus swap file...\033[0m"
remove_swap

echo -e "\033[93m[6/6] Mereset firewall...\033[0m"
reset_firewall

echo -e "\033[92mUninstall selesai! System akan reboot dalam 5 detik...\033[0m"
sleep 5
reboot
