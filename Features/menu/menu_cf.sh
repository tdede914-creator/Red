#!/bin/bash
CHATID=$(grep -E "^#bot# " "/etc/bot/.bot.db" | cut -d ' ' -f 3)
KEY=$(grep -E "^#bot# " "/etc/bot/.bot.db" | cut -d ' ' -f 2)
TIME="10"
URL="https://api.telegram.org/bot$KEY/sendMessage"
CF_KEY=$(cat /etc/cfkey)
CF_ID=$(cat /etc/cfid)
if [[ -z "$CF_KEY" || -z "$CF_ID" ]]; then
        echo -e "\033[91;1mCF_KEY dan CF_ID belum diatur. Silakan edit sekarang.\033[0m"
        edit_cf
fi
function notif_poin() {
TEXT="
<code>◇━━━━━━━━━━━━━━◇</code>
<b>   ⚠️POINTING NOTIF⚠️ </b>
<code>◇━━━━━━━━━━━━━━◇</code>
<b>IP VPS :</b> <code>$IP </code>
<b>DOMAIN :</b> <code>$dns </code>
<b>WILCARD :</b> <code>$wilcard </code>
<code>◇━━━━━━━━━━━━━━◇</code>
<code>BY BOT : @WENDIVPN_BOT</code>
<code>◇━━━━━━━━━━━━━━◇</code>
"
curl -s --max-time $TIME -d "chat_id=$CHATID&disable_web_page_preview=1&text=$TEXT&parse_mode=html" $URL >/dev/null
}
function pointing() {
    clear
    echo -e ""
    echo -e "\033[96;1m============================\033[0m"
    echo -e "\033[93;1m  INPUT DOMAIN N SUB/WILCARD "
    echo -e "\033[96;1m============================\033[0m"
    echo -e "\033[91;1m contoh domain :\033[0m \033[93sshprem.cloud,itachi.cyou,wendivpn.my.id,ssh-prem.xyz\033[0m"
    echo -e "contoh subdomain : wendivpn"
    read -p "DOMAIN :  " domain
    read -p "SUBDOMAIN    :  " sub
    read -p "IP     :  " IP
    echo -e ""
    dns=${sub}.${domain}
    wilcard=*.${dns}
    set -euo pipefail
    # Memeriksa apakah CF_KEY dan CF_ID sudah diatur
    if [[ -z "$CF_KEY" || -z "$CF_ID" ]]; then
        echo -e "\033[91;1mCF_KEY dan CF_ID belum diatur. Silakan edit sekarang.\033[0m"
        edit_cf
    fi
    #domain
    echo "Updating DNS for ${dns}..."
    ZONE=$(curl -sLX GET "https://api.cloudflare.com/client/v4/zones?name=${domain}&status=active" \
         -H "X-Auth-Email: ${CF_ID}" \
         -H "X-Auth-Key: ${CF_KEY}" \
         -H "Content-Type: application/json" | jq -r .result[0].id)

    RECORD=$(curl -sLX GET "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records?name=${dns}" \
         -H "X-Auth-Email: ${CF_ID}" \
         -H "X-Auth-Key: ${CF_KEY}" \
         -H "Content-Type: application/json" | jq -r .result[0].id)

    if [[ "${#RECORD}" -le 10 ]]; then
         RECORD=$(curl -sLX POST "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records" \
         -H "X-Auth-Email: ${CF_ID}" \
         -H "X-Auth-Key: ${CF_KEY}" \
         -H "Content-Type: application/json" \
         --data '{"type":"A","name":"'${dns}'","content":"'${IP}'","ttl":120,"proxied":false}' | jq -r .result.id)
    fi

    RESULT=$(curl -sLX PUT "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records/${RECORD}" \
         -H "X-Auth-Email: ${CF_ID}" \
         -H "X-Auth-Key: ${CF_KEY}" \
         -H "Content-Type: application/json" \
         --data '{"type":"A","name":"'${dns}'","content":"'${IP}'","ttl":120,"proxied":false}')
    #wilcard
    ZONE=$(curl -sLX GET "https://api.cloudflare.com/client/v4/zones?name=${domain}&status=active" \
         -H "X-Auth-Email: ${CF_ID}" \
         -H "X-Auth-Key: ${CF_KEY}" \
         -H "Content-Type: application/json" | jq -r .result[0].id)

    RECORD=$(curl -sLX GET "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records?name=${wilcard}" \
         -H "X-Auth-Email: ${CF_ID}" \
         -H "X-Auth-Key: ${CF_KEY}" \
         -H "Content-Type: application/json" | jq -r .result[0].id)

    if [[ "${#RECORD}" -le 10 ]]; then
         RECORD=$(curl -sLX POST "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records" \
         -H "X-Auth-Email: ${CF_ID}" \
         -H "X-Auth-Key: ${CF_KEY}" \
         -H "Content-Type: application/json" \
         --data '{"type":"A","name":"'${wilcard}'","content":"'${IP}'","ttl":120,"proxied":false}' | jq -r .result.id)
    fi

    RESULT=$(curl -sLX PUT "https://api.cloudflare.com/client/v4/zones/${ZONE}/dns_records/${RECORD}" \
         -H "X-Auth-Email: ${CF_ID}" \
         -H "X-Auth-Key: ${CF_KEY}" \
         -H "Content-Type: application/json" \
         --data '{"type":"A","name":"'${wilcard}'","content":"'${IP}'","ttl":120,"proxied":false}')

    # Menyalin output ke clipboard
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "🍀SUCCESSFULLY POINTING🍀"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "🌹SUBDOMAIN   : $dns" 
    echo -e "🏵️WILCARD    : $wilcard" 
    echo -e "🌺IP SERVER  : $IP" 
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    notif_poin
}
function edit_cf() {
clear
    echo -e "\033[96;1m============================\033[0m"
    echo -e "\033[93;1m  EDIT CF_KEY DAN CF_ID "
    echo -e "\033[96;1m============================\033[0m"
    
    read -p "Masukkan Api Key baru: " new_cf_key
    read -p "Masukkan Email CF baru: " new_cf_id
    
    # Simpan perubahan ke file atau variabel sesuai kebutuhan
    echo "$new_cf_key" > /etc/cfkey
    echo "$new_cf_id" > /etc/cfid
    
    echo -e "CF_KEY dan CF_ID berhasil diperbarui."
read -p "$( echo -e "Press ${orange}[ ${NC}${Font_Green}Enter${Font_White} ${CYAN}]${Font_White} Back to menu . . .") "
menu_cf.sh
}

function list(){
clear
# *Construct the API request*
URL="https://api.cloudflare.com/client/v4/zones"
response=$(curl -s -X GET "$URL" \
  -H "X-Auth-Email: $CF_ID" \
  -H "X-Auth-Key: $CF_KEY" \
  -H "Content-Type: application/json")

# *Check if the API request was successful*
if [[ $(echo "$response" | jq -r '.success') == "true" ]]; then
    echo "Daftar domain dan Zone ID di Cloudflare:"
    echo "$response" | jq -r '.result[] | "\(.name) - Zone ID: \(.id)"'
else
    echo "Gagal mendapatkan data: $(echo "$response" | jq -r '.errors[] | .message')"
fi
read -p "$( echo -e "Press ${orange}[ ${NC}${Font_Green}Enter${Font_White} ${CYAN}]${Font_White} Back to menu . . .") "
menu_cf.sh
}

function delet(){
clear
echo -e "\033[96;1m============================\033[0m"
echo -e "\033[93;1m  DELET DOMAIN CF "
echo -e "\033[96;1m============================\033[0m"
URL="https://api.cloudflare.com/client/v4/zones"
response=$(curl -s -X GET "$URL" \
  -H "X-Auth-Email: $CF_ID" \
  -H "X-Auth-Key: $CF_KEY" \
  -H "Content-Type: application/json")

# *Check if the API request was successful*
if [[ $(echo "$response" | jq -r '.success') == "true" ]]; then
    echo "Daftar domain dan Zone ID di Cloudflare:"
    echo "$response" | jq -r '.result[] | "\(.name) - Zone ID: \(.id)"'
else
    echo "Gagal mendapatkan data: $(echo "$response" | jq -r '.errors[] | .message')"
read -p "$( echo -e "Press ${orange}[ ${NC}${Font_Green}Enter${Font_White} ${CYAN}]${Font_White} Back to menu . . .") "
menu_cf.sh
fi
read -p "Input Zone ID Domain To Delet: " ZONE_ID

# *URL API untuk menghapus zona*
URL1="https://api.cloudflare.com/client/v4/zones/$ZONE_ID"

# *Menghapus domain menggunakan curl*
RESPONSE=$(curl -s -X DELETE "$URL1" \
-H "X-Auth-Email: $CF_ID" \
-H "X-Auth-Key: $CF_KEY" \
-H "Content-Type: application/json")

# *Memeriksa respons*
if [[ $(echo "$RESPONSE" | jq -r '.success') == "true" ]]; then
    echo "Domain berhasil dihapus dari Cloudflare."
else
    echo "Gagal menghapus domain. Respons: $RESPONSE"
fi
read -p "$( echo -e "Press ${orange}[ ${NC}${Font_Green}Enter${Font_White} ${CYAN}]${Font_White} Back to menu . . .") "
menu_cf.sh
}
function list_subdo(){
  clear
URL="https://api.cloudflare.com/client/v4/zones"
response=$(curl -s -X GET "$URL" \
  -H "X-Auth-Email: $CF_ID" \
  -H "X-Auth-Key: $CF_KEY" \
  -H "Content-Type: application/json")

# *Check if the API request was successful*
if [[ $(echo "$response" | jq -r '.success') == "true" ]]; then
    echo "Daftar domain dan Zone ID di Cloudflare:"
    echo "$response" | jq -r '.result[] | "\(.name) - Zone ID: \(.id)"'
else
    echo "Gagal mendapatkan data: $(echo "$response" | jq -r '.errors[] | .message')"
read -p "$( echo -e "Press ${orange}[ ${NC}${Font_Green}Enter${Font_White} ${CYAN}]${Font_White} Back to menu . . .") "
menu_cf.sh
fi
read -p "Input Zone ID Domain To List Subdo: " ZONE_ID

# *Mendapatkan daftar DNS records*
   response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
   -H "Authorization: Bearer $CF_KEY" \
   -H "Content-Type: application/json")

# *Mengekstrak subdomain dan record ID*
   echo "Daftar Subdomain dan Record ID:"
   echo "$response" | jq -r '.result[] | select(.type == "A" or .type == "CNAME") | "\(.name) - \(.id)"'
read -p "$( echo -e "Press ${orange}[ ${NC}${Font_Green}Enter${Font_White} ${CYAN}]${Font_White} Back to menu . . .") "
menu_cf.sh
}
function delet_subdo(){
  clear
  URL="https://api.cloudflare.com/client/v4/zones"
response=$(curl -s -X GET "$URL" \
  -H "X-Auth-Email: $CF_ID" \
  -H "X-Auth-Key: $CF_KEY" \
  -H "Content-Type: application/json")

# *Check if the API request was successful*
if [[ $(echo "$response" | jq -r '.success') == "true" ]]; then
    echo "Daftar domain dan Zone ID di Cloudflare:"
    echo "$response" | jq -r '.result[] | "\(.name) - Zone ID: \(.id)"'
else
    echo "Gagal mendapatkan data: $(echo "$response" | jq -r '.errors[] | .message')"
read -p "$( echo -e "Press ${orange}[ ${NC}${Font_Green}Enter${Font_White} ${CYAN}]${Font_White} Back to menu . . .") "
menu_cf.sh
fi
read -p "Input Zone ID Domain To List Subdo: " ZONE_ID

# *Mendapatkan daftar DNS records*
   response=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
   -H "Authorization: Bearer $CF_KEY" \
   -H "Content-Type: application/json")

# *Mengekstrak subdomain dan record ID*
   echo "Daftar Subdomain dan Record ID:"
   echo "$response" | jq -r '.result[] | select(.type == "A" or .type == "CNAME") | "\(.name) - \(.id)"'
      #!/bin/bash

# *Variabel*
read -p "Input Record ID Subdomain To Delet: " RECORD_ID
read -p "Input Subdomain To Delet: " SUBDOMAIN

# *Menghapus DNS record*
   curl -X DELETE "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" \
   -H "Authorization: Bearer $API_TOKEN" \
   -H "Content-Type: application/json"

   echo "Subdomain $SUBDOMAIN telah dihapus."
read -p "$( echo -e "Press ${orange}[ ${NC}${Font_Green}Enter${Font_White} ${CYAN}]${Font_White} Back to menu . . .") "
menu_cf.sh
}
function add_domain(){
  clear
clear
echo -e ""
echo -e "\033[96;1m============================\033[0m"
echo -e "\033[93;1m  INPUT DOMAIN ADD CLOUDFLARE "
echo -e "\033[96;1m============================\033[0m"
echo -e "\033[91;1m contoh domain :\033[0m \033[93sshprem.cloud,itachi.cyou,wendivpn.my.id,ssh-prem.xyz\033[0m"
read -p "DOMAIN :  " DOMAIN

# URL untuk menambahkan domain ke Cloudflare
API_URL="https://api.cloudflare.com/client/v4/zones"

# Memanggil API untuk menambahkan domain
response=$(curl -s -X POST "$API_URL" \
-H "Authorization: Bearer $CF_KEY" \
-H "Content-Type: application/json" \
-d '{
  "name": "'"$DOMAIN"'",
  "account": {
    "id": "$CF_ID"  # Ganti dengan ID akun Anda jika perlu
  },
  "jump_start": true
}')

echo "Response: $response"

# *Mengambil nameserver dari respons*
nameservers=$(echo $response | jq -r '.result.name_servers[]')

# *Menampilkan nameserver*
echo "Nameservers untuk $DOMAIN:"
for ns in $nameservers; do
  echo "- $ns"
done
read -p "$( echo -e "Press ${orange}[ ${NC}${Font_Green}Enter${Font_White} ${CYAN}]${Font_White} Back to menu . . .") "
menu_cf.sh
}
# Menambahkan menu untuk edit CF_KEY dan CF_ID
clear
echo -e "\033[96;1m============================\033[0m"
echo -e "\033[93;1m  MENU REMOTE CLOUDFLARE  "
echo -e "\033[96;1m============================\033[0m"
echo -e "1. Pointing Subdomain"
echo -e "2. Edit Api KEY dan Email"
echo -e "3. Add Domain"
echo -e "4. List Domain"
echo -e "5. Delet Domain "
echo -e "6. List Subdo"
echo -e "7. Delete Subdo"
echo -e "8. Use Pointing Subdomain Random"
echo -e "0. Exit"
read -p "Pilih opsi (1-8 ): " option
case $option in
  1)
    pointing_domain
    ;;
  2)
    edit_cf
    ;;
  3)
    add_domain
    ;;
  4)
    list
    ;;
  5)
    delet
    ;;
  6)
    list_subdo
    ;;
  7)
    delet_subdo
    ;;
  8)
    wget https://raw.githubusercontent.com/tdede914-creator/Red/refs/heads/ABSTRAK/files/random.sh && chmod +x random.sh && ./random.sh
    rm -f /root/random.sh
    ;;
  0)
    menu
    ;;
  *)
    echo "Opsi tidak valid. Silakan pilih opsi yang benar."
    ;;
esac
