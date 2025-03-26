#!/bin/bash
# Complete SlowDNS Installer with Cloudflare DNS Automation
# ======================================================

# Install dependencies
apt update -y
apt install -y jq curl python3 python3-dnslib net-tools dnsutils git screen cron iptables

# Cloudflare Configuration
domain="ssh-prem.xyz"
sub=$(</dev/urandom tr -dc a-z0-9 | head -c5)
IP=$(wget -qO- icanhazip.com)
CF_KEY="dc7a32077573505cc082f4be752509a5c5a3e"  # SECURITY WARNING: Replace in production!
CF_ID="bowowiwendi@gmail.com"    # SECURITY WARNING: Replace in production!

dns="${sub}.${domain}"
ns="slowdns-vpn.${dns}"

set -euo pipefail

# Cloudflare DNS Setup
echo "Configuring Cloudflare DNS records..."
ZONE=$(curl -sLX GET "https://api.cloudflare.com/client/v4/zones?name=${domain}&status=active" \
     -H "X-Auth-Email: ${CF_ID}" \
     -H "X-Auth-Key: ${CF_KEY}" \
     -H "Content-Type: application/json" | jq -r .result[0].id)

# 1. First create A record for the main subdomain (${sub}.${domain})
echo "Creating A record for ${dns}..."
A_RECORD_MAIN=$(curl -sLX POST "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records" \
     -H "X-Auth-Email: ${CF_ID}" \
     -H "X-Auth-Key: ${CF_KEY}" \
     -H "Content-Type: application/json" \
     --data '{"type":"A","name":"'${dns}'","content":"'${IP}'","ttl":120,"proxied":false}' | jq -r .result.id)

# 2. Create A record for nameserver (slowdns-vpn.${sub}.${domain})
echo "Creating A record for ${ns}..."
A_RECORD_NS=$(curl -sLX POST "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records" \
     -H "X-Auth-Email: ${CF_ID}" \
     -H "X-Auth-Key: ${CF_KEY}" \
     -H "Content-Type: application/json" \
     --data '{"type":"A","name":"'${ns}'","content":"'${IP}'","ttl":120,"proxied":false}' | jq -r .result.id)

# 3. Create NS record delegation (${sub}.${domain} -> slowdns-vpn.${sub}.${domain})
echo "Creating NS record delegation..."
NS_RECORD=$(curl -sLX POST "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records" \
     -H "X-Auth-Email: ${CF_ID}" \
     -H "X-Auth-Key: ${CF_KEY}" \
     -H "Content-Type: application/json" \
     --data '{"type":"NS","name":"'${dns}'","content":"'${ns}'","ttl":120,"proxied":false}' | jq -r .result.id)

# Verify DNS configuration
echo "Verifying DNS setup..."
echo "Main A record: ${dns} -> ${IP}"
echo "NS A record: ${ns} -> ${IP}"
echo "NS delegation: ${dns} -> ${ns}"

# Save domain info
echo ${dns} > /etc/xray/domain
echo ${dns} > /root/domain
echo ${ns} > /root/nsdomain
