#!/bin/bash
z="\033[1;93m"
clear
#read -rp "Masukan Subdomain kamu (Contoh: Zhee121): " -e sub
#DOMAIN=rstore-vpn.cloud
#SUB_DOMAIN=${sub}.rstore-vpn.cloud
#CF_ID=ridwanstoreaws@gmail.com
#CF_KEY=4ecfe9035f4e6e60829e519bd5ee17d66954f
function auto-dns(){
sub=sc-`</dev/urandom tr -dc a-z0-9 | head -c5`
DOMAIN=vpn-prem.biz.id
SUB_DOMAIN=${sub}.vpn-prem.biz.id
CF_ID=padliapandi459@gmail.com
CF_KEY=1a700ef4a22e642f0ea8d43420bb0b1237589
set -euo pipefail
IP=$(curl -sS ipv4.icanhazip.com);
echo "Updating DNS for ${SUB_DOMAIN}..."
ZONE=$(curl -sLX GET "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN}&status=active" \
     -H "X-Auth-Email: ${CF_ID}" \
     -H "X-Auth-Key: ${CF_KEY}" \
     -H "Content-Type: application/json" | jq -r .result[0].id)

RECORD=$(curl -sLX GET "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records?name=${SUB_DOMAIN}" \
     -H "X-Auth-Email: ${CF_ID}" \
     -H "X-Auth-Key: ${CF_KEY}" \
     -H "Content-Type: application/json" | jq -r .result[0].id)

if [[ "${#RECORD}" -le 10 ]]; then
     RECORD=$(curl -sLX POST "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records" \
     -H "X-Auth-Email: ${CF_ID}" \
     -H "X-Auth-Key: ${CF_KEY}" \
     -H "Content-Type: application/json" \
     --data '{"type":"A","name":"'${SUB_DOMAIN}'","content":"'${IP}'","ttl":120,"proxied":false}' | jq -r .result.id)
fi

RESULT=$(curl -sLX PUT "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records/${RECORD}" \
     -H "X-Auth-Email: ${CF_ID}" \
     -H "X-Auth-Key: ${CF_KEY}" \
     -H "Content-Type: application/json" \
     --data '{"type":"A","name":"'${SUB_DOMAIN}'","content":"'${IP}'","ttl":120,"proxied":false}')

echo "$SUB_DOMAIN" > /root/domain
rm -f /root/cf.sh
echo -e "Selesai"
read -p "press !! [ ENTER ] To menu"
menu
}
function dns(){
read -rp "Masukan Subdomain kamu (Contoh: Wendi99): " -e sub
DOMAIN=vpn-prem.biz.id
SUB_DOMAIN=${sub}.vpn-prem.biz.id
CF_ID=padliapandi459@gmail.com
CF_KEY=1a700ef4a22e642f0ea8d43420bb0b1237589
set -euo pipefail
IP=$(curl -sS ipv4.icanhazip.com);
echo "Updating DNS for ${SUB_DOMAIN}..."
ZONE=$(curl -sLX GET "https://api.cloudflare.com/client/v4/zones?name=${DOMAIN}&status=active" \
     -H "X-Auth-Email: ${CF_ID}" \
     -H "X-Auth-Key: ${CF_KEY}" \
     -H "Content-Type: application/json" | jq -r .result[0].id)

RECORD=$(curl -sLX GET "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records?name=${SUB_DOMAIN}" \
     -H "X-Auth-Email: ${CF_ID}" \
     -H "X-Auth-Key: ${CF_KEY}" \
     -H "Content-Type: application/json" | jq -r .result[0].id)

if [[ "${#RECORD}" -le 10 ]]; then
     RECORD=$(curl -sLX POST "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records" \
     -H "X-Auth-Email: ${CF_ID}" \
     -H "X-Auth-Key: ${CF_KEY}" \
     -H "Content-Type: application/json" \
     --data '{"type":"A","name":"'${SUB_DOMAIN}'","content":"'${IP}'","ttl":120,"proxied":false}' | jq -r .result.id)
fi

RESULT=$(curl -sLX PUT "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records/${RECORD}" \
     -H "X-Auth-Email: ${CF_ID}" \
     -H "X-Auth-Key: ${CF_KEY}" \
     -H "Content-Type: application/json" \
     --data '{"type":"A","name":"'${SUB_DOMAIN}'","content":"'${IP}'","ttl":120,"proxied":false}')

echo "$SUB_DOMAIN" > /root/domain
rm -f /root/cf.sh
echo -e "Selesai"
read -p "press !! [ ENTER ] To menu"
menu
}

echo -e "\033[96m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e " \e[1;971m                   MENU EXTRA                        \e[0m"
echo -e "\033[96m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${grenbo}[1]${NC}${YELL} MENU NOOBZ ${NC}"
echo -e "  ${grenbo}[2]${NC}${YELL} Auto Change Sub DNS ${NC}"
echo -e "  ${grenbo}[3]${NC}${YELL} Manual Change Sub DNS ${NC}"
echo -e "  ${grenbo}[4]${NC}${YELL} Install SLW DNS ${NC}"
echo -e "  ${grenbo}[5]${NC}${YELL} MENU THEME ${NC}"
echo -e ""
echo -e "  ${grenbo}[0]${NC}${YELL} Back To Menu${NC}"
echo -e ""
read -p "  Select From Options [ 1 - 3 or 0 ] : " menu
case $menu in
1) clear ;
    noobz
    ;;
2) clear ;
    auto-dns
    ;;
3) clear ;
    dns
    ;;
4) clear ;
    wget https://raw.githubusercontent.com/fisabiliyusri/Mantap/main/SLDNS/install-sldns && chmod +x install-sldns && ./install-sldns
    ;;
5) clear ;
    menu-theme.sh
    ;;
0) clear ;
    menu
    ;;
*) clear ;
    menu
    ;;
esac