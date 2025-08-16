#!/bin/bash
# Decrypted by LT | FUSCATOR
# Github- https://github.com/LunaticTunnel/Absurd
# Disesuaikan untuk Ubuntu 24.04
# Koreksi oleh Assistant AI

export DEBIAN_FRONTEND=noninteractive
OS=$(uname -m)
# MYIP=$(wget -qO- ipinfo.io/ip); # Tidak digunakan dalam skrip ini
# domain=$(cat /root/domain) # Diasumsikan sudah dibuat oleh skrip utama
# Periksa apakah file domain ada
if [[ ! -f /root/domain ]]; then
    echo "ERROR: File /root/domain tidak ditemukan. Pastikan domain telah disetel sebelum menjalankan skrip ini."
    exit 1
fi
domain=$(cat /root/domain)
MYIP2="s/xxxxxxxxx/$domain/g"

function print_status() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

function ovpn_install() {
    print_status "Menginstal dan mengekstrak konfigurasi OpenVPN..."
    rm -rf /etc/openvpn
    mkdir -p /etc/openvpn

    # Perbarui daftar paket
    print_status "Memperbarui daftar paket..."
    sudo apt update
    if [[ $? -ne 0 ]]; then
        echo "ERROR: Gagal memperbarui daftar paket."
        exit 1
    fi

    # Instal paket OpenVPN dan plugin PAM
    print_status "Menginstal paket openvpn dan openvpn-plugin-auth-pam..."
    sudo apt install -y openvpn openvpn-plugin-auth-pam
    if [[ $? -ne 0 ]]; then
        echo "ERROR: Gagal menginstal paket openvpn atau openvpn-plugin-auth-pam."
        exit 1
    fi

    # Unduh file konfigurasi
    print_status "Mengunduh file konfigurasi vpn.zip..."
    # Perbaiki URL: Pastikan tidak ada spasi tambahan di akhir
    wget -O /etc/openvpn/vpn.zip "https://github.com/bowowiwendi/WendyVpn/raw/refs/heads/ABSTRAK/ovpn/vpn.zip" >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo "ERROR: Gagal mengunduh file vpn.zip dari URL."
        exit 1
    fi

    # Ekstrak file konfigurasi
    print_status "Mengekstrak file konfigurasi..."
    unzip -q -d /etc/openvpn/ /etc/openvpn/vpn.zip
    if [[ $? -ne 0 ]]; then
        echo "ERROR: Gagal mengekstrak file /etc/openvpn/vpn.zip."
        exit 1
    fi
    rm -f /etc/openvpn/vpn.zip

    # Pastikan kepemilikan direktori easy-rsa benar
    if [ -d "/etc/openvpn/server/easy-rsa/" ]; then
        chown -R root:root /etc/openvpn/server/easy-rsa/
        print_status "Kepemilikan /etc/openvpn/server/easy-rsa/ diatur ke root:root."
    else
        echo "Peringatan: Direktori /etc/openvpn/server/easy-rsa/ tidak ditemukan setelah ekstraksi."
    fi
    print_status "Instalasi OpenVPN awal selesai."
}

function config_easy() {
    print_status "Mengkonfigurasi OpenVPN..."
    cd

    # Buat direktori plugin jika belum ada dan salin plugin PAM dengan penanganan error
    mkdir -p /usr/lib/openvpn/
    PLUGIN_SOURCE="/usr/lib/x86_64-linux-gnu/openvpn/plugins/openvpn-plugin-auth-pam.so"
    PLUGIN_DEST="/usr/lib/openvpn/openvpn-plugin-auth-pam.so"
    if [[ -f "$PLUGIN_SOURCE" ]]; then
        cp "$PLUGIN_SOURCE" "$PLUGIN_DEST"
        print_status "Plugin PAM disalin ke $PLUGIN_DEST"
    else
        echo "Peringatan: Plugin PAM tidak ditemukan di $PLUGIN_SOURCE. Autentikasi PAM mungkin tidak berfungsi."
        # Catatan: Anda mungkin perlu menyesuaikan path dalam file konfigurasi .conf nanti jika penyalinan gagal
        # Atau, instalasi paket mungkin tidak menyertakan plugin ini di path ini.
        # Cek path lain yang umum:
        PLUGIN_ALT_SOURCE=$(find /usr/lib -name "openvpn-plugin-auth-pam.so" 2>/dev/null | head -n 1)
        if [[ -n "$PLUGIN_ALT_SOURCE" ]]; then
             echo "Plugin PAM ditemukan di lokasi alternatif: $PLUGIN_ALT_SOURCE. Menyalin..."
             cp "$PLUGIN_ALT_SOURCE" "$PLUGIN_DEST"
             print_status "Plugin PAM disalin dari lokasi alternatif ke $PLUGIN_DEST"
        else
             echo "Plugin PAM tidak ditemukan di lokasi alternatif juga."
        fi
    fi
    chmod 755 /usr/lib/openvpn/ # Pastikan direktori dapat diakses

    # Aktifkan autostart (ini untuk konfigurasi lama, mungkin tidak diperlukan lagi)
    # Tapi tetap dilakukan untuk kompatibilitas
    if [[ -f /etc/default/openvpn ]]; then
        sed -i 's/#AUTOSTART="all"/AUTOSTART="all"/g' /etc/default/openvpn
        print_status "Konfigurasi /etc/default/openvpn diperbarui."
    else
        echo "Peringatan: File /etc/default/openvpn tidak ditemukan. Membuat file kosong."
        touch /etc/default/openvpn
        echo 'AUTOSTART="all"' >> /etc/default/openvpn
        print_status "File /etc/default/openvpn dibuat dan dikonfigurasi."
    fi

    # Aktifkan dan mulai instance server spesifik
    # Pastikan server-tcp.conf dan server-udp.conf ada di /etc/openvpn/server/
    # Kita asumsikan nama file konfigurasinya adalah server-tcp.conf dan server-udp.conf
    print_status "Mengaktifkan dan memulai layanan openvpn-server@server-tcp..."
    systemctl enable --now openvpn-server@server-tcp || { echo "ERROR: Gagal mengaktifkan/memulai openvpn-server@server-tcp"; exit 1; }

    print_status "Mengaktifkan dan memulai layanan openvpn-server@server-udp..."
    systemctl enable --now openvpn-server@server-udp || { echo "ERROR: Gagal mengaktifkan/memulai openvpn-server@server-udp"; exit 1; }

    # Ganti /etc/init.d/openvpn restart dengan systemctl
    # Merestart instance spesifik yang telah diaktifkan:
    print_status "Merestart layanan OpenVPN server..."
    systemctl restart openvpn-server@server-tcp || { echo "ERROR: Gagal merestart openvpn-server@server-tcp"; exit 1; }
    systemctl restart openvpn-server@server-udp || { echo "ERROR: Gagal merestart openvpn-server@server-udp"; exit 1; }

    print_status "Konfigurasi OpenVPN selesai."
}

function make_follow() {
    print_status "Mengkonfigurasi IP forwarding dan file .ovpn..."
    # Aktifkan IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf
    print_status "IP forwarding diaktifkan."

    # Buat file konfigurasi client
    cat > /etc/openvpn/tcp.ovpn <<-END
client
dev tun
proto tcp
remote xxxxxxxxx 1194
resolv-retry infinite
route-method exe
nobind
persist-key
persist-tun
auth-user-pass
comp-lzo
verb 3
END
    sed -i $MYIP2 /etc/openvpn/tcp.ovpn;

    cat > /etc/openvpn/udp.ovpn <<-END
client
dev tun
proto udp
remote xxxxxxxxx 2200
resolv-retry infinite
route-method exe
nobind
persist-key
persist-tun
auth-user-pass
comp-lzo
verb 3
END
    sed -i $MYIP2 /etc/openvpn/udp.ovpn;

    cat > /etc/openvpn/ws-ssl.ovpn <<-END
client
dev tun
proto tcp
remote xxxxxxxxx 443
resolv-retry infinite
route-method exe
nobind
persist-key
persist-tun
auth-user-pass
comp-lzo
verb 3
END
    sed -i $MYIP2 /etc/openvpn/ws-ssl.ovpn;

    cat > /etc/openvpn/ssl.ovpn <<-END
client
dev tun
proto tcp
remote xxxxxxxxx 443
resolv-retry infinite
route-method exe
nobind
persist-key
persist-tun
auth-user-pass
comp-lzo
verb 3
END
    sed -i $MYIP2 /etc/openvpn/ssl.ovpn;

    print_status "File konfigurasi client (.ovpn) dibuat."
}

function cert_ovpn() {
    print_status "Menambahkan sertifikat CA ke file .ovpn dan membuat arsip..."

    # Periksa keberadaan CA certificate
    if [[ ! -f /etc/openvpn/server/ca.crt ]]; then
        echo "ERROR: File sertifikat CA (/etc/openvpn/server/ca.crt) tidak ditemukan."
        exit 1
    fi

    # Tambahkan CA cert ke file konfigurasi client
    echo '<ca>' >> /etc/openvpn/tcp.ovpn
    cat /etc/openvpn/server/ca.crt >> /etc/openvpn/tcp.ovpn
    echo '</ca>' >> /etc/openvpn/tcp.ovpn
    cp /etc/openvpn/tcp.ovpn /var/www/html/tcp.ovpn

    echo '<ca>' >> /etc/openvpn/udp.ovpn
    cat /etc/openvpn/server/ca.crt >> /etc/openvpn/udp.ovpn
    echo '</ca>' >> /etc/openvpn/udp.ovpn
    cp /etc/openvpn/udp.ovpn /var/www/html/udp.ovpn

    echo '<ca>' >> /etc/openvpn/ws-ssl.ovpn
    cat /etc/openvpn/server/ca.crt >> /etc/openvpn/ws-ssl.ovpn
    echo '</ca>' >> /etc/openvpn/ws-ssl.ovpn
    cp /etc/openvpn/ws-ssl.ovpn /var/www/html/ws-ssl.ovpn

    # PERBAIKI: Kesalahan ketik dan file yang salah disalin
    # SALAH: echo '</ca>' >> /etc/openvpn/ssl.ovpn # Ini menutup tag yang tidak dibuka
    # SALAH: cp /etc/openvpn/ws-ssl.ovpn /var/www/html/ssl.ovpn # Ini menyalin ws-ssl.ovpn ke ssl.ovpn
    # BENAR:
    echo '<ca>' >> /etc/openvpn/ssl.ovpn # Buka tag <ca>
    cat /etc/openvpn/server/ca.crt >> /etc/openvpn/ssl.ovpn
    echo '</ca>' >> /etc/openvpn/ssl.ovpn # Tutup tag <ca>
    cp /etc/openvpn/ssl.ovpn /var/www/html/ssl.ovpn # Salin file ssl.ovpn yang benar

    # Buat arsip ZIP
    cd /var/www/html/
    zip Kyt-Project.zip tcp.ovpn udp.ovpn ssl.ovpn ws-ssl.ovpn > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo "Peringatan: Gagal membuat arsip Kyt-Project.zip."
    fi
    cd

    # Buat halaman index.html
    cat <<'mySiteOvpn' > /var/www/html/index.html
<!DOCTYPE html>
<html lang="en">
<!-- Simple OVPN Download site -->
<head><meta charset="utf-8" /><title>OVPN Config Download</title><meta name="description" content="Server" /><meta content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" name="viewport" /><meta name="theme-color" content="#000000" /><link rel="stylesheet" href="https://use.fontawesome.com/releases/v5.8.2/css/all.css"><link href="https://cdnjs.cloudflare.com/ajax/libs/twitter-bootstrap/4.3.1/css/bootstrap.min.css" rel="stylesheet"><link href="https://cdnjs.cloudflare.com/ajax/libs/mdbootstrap/4.8.3/css/mdb.min.css" rel="stylesheet"></head><body><div class="container justify-content-center" style="margin-top:9em;margin-bottom:5em;"><div class="col-md"><div class="view"><img src="https://openvpn.net/wp-content/uploads/openvpn.jpg" class="card-img-top"><div class="mask rgba-white-slight"></div></div><div class="card"><div class="card-body"><h5 class="card-title">Config List</h5><br /><ul class="list-group">
<li class="list-group-item justify-content-between align-items-center" style="margin-bottom:1em;"><p>TCP <span class="badge light-blue darken-4">Android/iOS/PC/Modem</span><br /><small></small></p><a class="btn btn-outline-success waves-effect btn-sm" href="https://IP-ADDRESSS:81/tcp.ovpn" style="float:right;"><i class="fa fa-download"></i> Download</a></li>
<li class="list-group-item justify-content-between align-items-center" style="margin-bottom:1em;"><p>UDP <span class="badge light-blue darken-4">Android/iOS/PC/Modem</span><br /><small></small></p><a class="btn btn-outline-success waves-effect btn-sm" href="https://IP-ADDRESSS:81/udp.ovpn" style="float:right;"><i class="fa fa-download"></i> Download</a></li>
<li class="list-group-item justify-content-between align-items-center" style="margin-bottom:1em;"><p>SSL <span class="badge light-blue darken-4">Android/iOS/PC/Modem</span><br /><small></small></p><a class="btn btn-outline-success waves-effect btn-sm" href="https://IP-ADDRESSS:81/ssl.ovpn" style="float:right;"><i class="fa fa-download"></i> Download</a></li>
<li class="list-group-item justify-content-between align-items-center" style="margin-bottom:1em;"><p> WS SSL <span class="badge light-blue darken-4">Android/iOS/PC/Modem</span><br /><small></small></p><a class="btn btn-outline-success waves-effect btn-sm" href="https://IP-ADDRESSS:81/ws-ssl.ovpn" style="float:right;"><i class="fa fa-download"></i> Download</a></li>
<li class="list-group-item justify-content-between align-items-center" style="margin-bottom:1em;"><p> ALL.zip <span class="badge light-blue darken-4">Android/iOS/PC/Modem</span><br /><small></small></p><a class="btn btn-outline-success waves-effect btn-sm" href="https://IP-ADDRESSS:81/Kyt-Project.zip" style="float:right;"><i class="fa fa-download"></i> Download</a></li>
</ul></div></div></div></div></body></html>
mySiteOvpn
    # Ganti placeholder IP dengan IP publik aktual
    sed -i "s|IP-ADDRESSS|$(curl -sS ifconfig.me)|g" /var/www/html/index.html
    print_status "Sertifikat ditambahkan ke file .ovpn, arsip dibuat, dan halaman index.html diperbarui."
}

function install_ovpn() {
    print_status "========== MENJALANKAN install_ovpn =========="
    ovpn_install
    config_easy
    make_follow
    # HAPUS baris berikut yang menyebabkan duplikasi:
    # make_follow
    cert_ovpn

    # HAPUS atau komentari baris-baris berikut yang tidak sesuai dan redundan:
    # systemctl enable openvpn # Tidak sesuai untuk instance spesifik
    # systemctl start openvpn   # Tidak sesuai untuk instance spesifik
    # /etc/init.d/openvpn restart # Diganti dengan systemctl

    # Restart layanan (seharusnya sudah dilakukan di config_easy, tapi tambahkan sebagai jaga-jaga)
    print_status "Merestart layanan OpenVPN untuk memastikan..."
    systemctl restart openvpn-server@server-tcp || echo "Peringatan: Gagal merestart openvpn-server@server-tcp"
    systemctl restart openvpn-server@server-udp || echo "Peringatan: Gagal merestart openvpn-server@server-udp"

    print_status "========== install_ovpn SELESAI =========="
}

# Jalankan fungsi utama
install_ovpn
