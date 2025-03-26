#!/bin/bash
# Complete SlowDNS Installer with Cloudflare DNS Automation
apt install -y jq curl

# Configuration
domain="ssh-prem.xyz"
sub=$(</dev/urandom tr -dc a-z0-9 | head -c5)
IP=$(wget -qO- icanhazip.com)
CF_KEY="dc7a32077573505cc082f4be752509a5c5a3e"
CF_ID="bowowiwendi@gmail.com"

dns="${sub}.${domain}"
ns="slowdns-vpn.${dns}"

set -euo pipefail

# Cloudflare API Functions
get_zone_id() {
    curl -sLX GET "https://api.cloudflare.com/client/v4/zones?name=${domain}&status=active" \
    -H "X-Auth-Email: ${CF_ID}" \
    -H "X-Auth-Key: ${CF_KEY}" \
    -H "Content-Type: application/json" | jq -r .result[0].id
}

create_record() {
    local type=$1 name=$2 content=$3
    curl -sLX POST "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records" \
    -H "X-Auth-Email: ${CF_ID}" \
    -H "X-Auth-Key: ${CF_KEY}" \
    -H "Content-Type: application/json" \
    --data '{"type":"'${type}'","name":"'${name}'","content":"'${content}'","ttl":120,"proxied":false}' | jq -r .result.id
}

# Main DNS Setup
echo "⏳ Configuring Cloudflare DNS records..."
ZONE=$(get_zone_id)

echo "🔧 Creating A record for ${dns}..."
create_record A "${dns}" "${IP}"

echo "🔧 Creating A record for ${ns}..."
create_record A "${ns}" "${IP}"

echo "🔧 Creating NS delegation..."
create_record NS "${dns}" "${ns}"

# Save domain info
echo ${dns} > /etc/xray/domain
echo ${dns} > /root/domain
echo ${ns} > /root/nsdomain

echo "✅ DNS Setup Complete!"
echo "   Subdomain: ${dns}"
echo "   Nameserver: ${ns}"
echo "   Please wait for DNS propagation (5 minutes)"
