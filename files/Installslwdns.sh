#!/bin/bash
# install-slowdns.sh - SlowDNS Installation
# Usage: ./install-slowdns.sh

# Check existing domain config
if [ -f /etc/xray/domain ]; then
    full_domain=$(cat /etc/xray/domain)
    IFS='.' read -r sub main_domain <<< "$full_domain"
    
    echo "ℹ️ Detected existing domain configuration:"
    echo "   Full Domain: $full_domain"
    echo "   Main Domain: $main_domain"
    echo "   Subdomain: $sub"
    
    read -p "Use detected domain? [Y/n]: " use_detected
    if [[ "$use_detected" =~ ^[Nn]$ ]]; then
        read -p "Enter new full domain (e.g. sub.example.com): " full_domain
        IFS='.' read -r sub main_domain <<< "$full_domain"
    fi
else
    read -p "Enter full domain (e.g. sub.example.com): " full_domain
    IFS='.' read -r sub main_domain <<< "$full_domain"
fi

# Validate domain structure
if [[ -z "$sub" || -z "$main_domain" ]]; then
    echo "❌ Error: Invalid domain format. Use format: subdomain.domain.tld"
    exit 1
fi

IP=$(wget -qO- icanhazip.com)
CF_KEY="dc7a32077573505cc082f4be752509a5c5a3e"
CF_ID="bowowiwendi@gmail.com"
echo ""

# Configuration
dns="$full_domain"
ns="slowdns-vpn.$dns"

set -euo pipefail

# Cloudflare API Functions
get_zone_id() {
    response=$(curl -sLX GET "https://api.cloudflare.com/client/v4/zones?name=${main_domain}&status=active" \
    -H "X-Auth-Email: ${CF_ID}" \
    -H "X-Auth-Key: ${CF_KEY}" \
    -H "Content-Type: application/json")
    
    if echo "$response" | jq -e '.success == true' >/dev/null; then
        echo "$response" | jq -r '.result[0].id'
    else
        echo "❌ Error getting Zone ID: $(echo "$response" | jq -r '.errors[0].message')"
        exit 1
    fi
}

create_record() {
    local type=$1 name=$2 content=$3
    response=$(curl -sLX POST "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records" \
    -H "X-Auth-Email: ${CF_ID}" \
    -H "X-Auth-Key: ${CF_KEY}" \
    -H "Content-Type: application/json" \
    --data '{"type":"'${type}'","name":"'${name}'","content":"'${content}'","ttl":120,"proxied":false}')
    
    if echo "$response" | jq -e '.success == true' >/dev/null; then
        echo "$response" | jq -r '.result.id'
    else
        echo "❌ Error creating ${type} record for ${name}: $(echo "$response" | jq -r '.errors[0].message')"
        exit 1
    fi
}

# Main DNS Setup
echo -e "\n⏳ Configuring Cloudflare DNS records..."
ZONE=$(get_zone_id)
echo "✔️ Zone ID: ${ZONE}"

echo -e "\n🔧 Creating A record for ${ns}..."
create_record A "${ns}" "${IP}"

echo -e "\n🔧 Creating NS delegation..."
create_record NS "${dns}" "${ns}"

# Save domain info
mkdir -p /etc/slowdns
echo "${dns}" | tee /etc/xray/domain /root/domain /etc/slowdns/domain >/dev/null
echo "${ns}" > /root/nsdomain

echo -e "\n✅ DNS Setup Complete!"
echo "========================================"
echo "   Detected Configuration:"
echo "   Full Domain: ${dns}"
echo "   Main Domain: ${main_domain}"
echo "   Subdomain: ${sub}"
echo "   Nameserver: ${ns}"
echo "   Server IP: ${IP}"
echo "========================================"
echo -e "\n⚠️ Please wait for DNS propagation before using"
echo "Check with: dig +short ${dns} && dig +short NS ${dns}"
# Verify DNS config exists
if [ ! -f /root/nsdomain ]; then
    echo "❌ Error: DNS configuration not found. Run setup-dns.sh first!"
    exit 1
fi

# Install dependencies
echo "⏳ Installing dependencies..."
apt update -y
apt install -y python3 python3-dnslib net-tools dnsutils iptables

# Setup SlowDNS
echo "🔧 Configuring SlowDNS..."
mkdir -p /etc/slowdns
wget -qO /etc/slowdns/server.key "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/server.key"
wget -qO /etc/slowdns/server.pub "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/server.pub"
wget -qO /etc/slowdns/sldns-server "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-server"
wget -qO /etc/slowdns/sldns-client "https://raw.githubusercontent.com/fisabiliyusri/SLDNS/main/slowdns/sldns-client"
chmod +x /etc/slowdns/{server.key,server.pub,sldns-server,sldns-client}

# Configure services
echo "📝 Creating service files..."
cat > /etc/systemd/system/client-sldns.service << EOF
[Unit]
Description=Client SlowDNS
After=network.target

[Service]
Type=simple
User=root
ExecStart=/etc/slowdns/sldns-client -udp 8.8.8.8:53 --pubkey-file /etc/slowdns/server.pub $(cat /root/nsdomain) 127.0.0.1:2222
Restart=always

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/server-sldns.service << EOF
[Unit]
Description=Server SlowDNS
After=network.target

[Service]
Type=simple
User=root
ExecStart=/etc/slowdns/sldns-server -udp :5300 -privkey-file /etc/slowdns/server.key $(cat /root/nsdomain) 127.0.0.1:2269
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Firewall rules
echo "🔥 Configuring firewall..."
iptables -I INPUT -p udp --dport 5300 -j ACCEPT
iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 5300
netfilter-persistent save
netfilter-persistent reload

# SSH Configuration
echo "🔒 Adding SSH ports..."
echo "Port 2222" >> /etc/ssh/sshd_config
echo "Port 2269" >> /etc/ssh/sshd_config
sed -i 's/#AllowTcpForwarding yes/AllowTcpForwarding yes/g' /etc/ssh/sshd_config
systemctl restart ssh

# Enable services
echo "🚀 Starting services..."
systemctl daemon-reload
systemctl enable --now client-sldns server-sldns

echo "✅ SlowDNS Installation Complete!"
echo "   SSH Ports: 2222 (Client), 2269 (Server)"
echo "   Check status with: systemctl status client-sldns server-sldns"
