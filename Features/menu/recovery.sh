#!/bin/bash
now=$(date +"%Y-%m-%d")
MYIP=$(wget -qO- ipinfo.io/ip)
clear

# Initialize arrays to store locked accounts for each protocol
declare -A locked_accounts=(
    [vmess]=()
    [ssh]=()
    [vless]=()
    [trojan]=()
    [shadowsocks]=()
)

function format_message() {
    local protocol=$1
    local -n accounts=$2
    
    if [ ${#accounts[@]} -eq 0 ]; then
        return
    fi
    
    # Prepare the message with header
    local message="
<code>──────────────────────────</code>
<b>⚠️ NOTIF EXP ${protocol^^} LOCKED ⚠️</b>
<code>──────────────────────────</code>
<b>🔒 Total locked: ${#accounts[@]}</b>
<b>📅 Date: $now</b>
<code>──────────────────────────</code>
"

    # Add each locked account with consistent formatting
    for account in "${accounts[@]}"; do
        # Format username with consistent width (25 chars)
        message+="<code>🔐 $(printf "%-25s" "$account")</code>\n"
    done
    
    message+="<code>──────────────────────────</code>"
    
    echo "$message"
}

function send_notification() {
    local protocol=$1
    local -n accounts=$2
    
    if [ ${#accounts[@]} -eq 0 ]; then
        return
    fi
    
    CHATID=$(grep -E "^#bot# " "/etc/bot/.bot.db" | cut -d ' ' -f 3)
    KEY=$(grep -E "^#bot# " "/etc/bot/.bot.db" | cut -d ' ' -f 2)
    TIME="10"
    URL="https://api.telegram.org/bot$KEY/sendMessage"
    
    local message=$(format_message "$protocol" accounts)
    
    # Send the notification
    curl -s --max-time $TIME -d "chat_id=$CHATID&disable_web_page_preview=1&text=$message&parse_mode=html" $URL >/dev/null
}

##----- Auto Lock Vmess
data=($(cat /etc/xray/config.json | grep '^###' | cut -d ' ' -f 2 | sort | uniq))
for user in "${data[@]}"; do
    exp=$(grep -w "^### $user" "/etc/xray/config.json" | cut -d ' ' -f 3 | sort | uniq)
    d1=$(date -d "$exp" +%s)
    d2=$(date -d "$now" +%s)
    exp2=$(((d1 - d2) / 86400))
    if [[ "$exp2" -le "0" ]]; then
        uuid=$(grep -E "^},{" "/etc/xray/config.json" | grep -wE '"'"${user}"'"' | cut -d " " -f 2 | cut -d '"' -f 2 | uniq)
        sed -i '/#vmess$/a\### '"$user $exp $uuid"'' /etc/xray/.lock.db
        sed -i "/^### $user/,/^},{/d" /etc/xray/config.json
        sed -i "/^## $user/,/^},{/d" /etc/xray/config.json
        systemctl restart xray > /dev/null 2>&1
        echo "[VMESS] 🔒 $user expired on $exp"
        locked_accounts[vmess]+=("$user")
    fi
done

#----- Auto Lock Vless
data=($(cat /etc/xray/config.json | grep '^#&' | cut -d ' ' -f 2 | sort | uniq))
for user in "${data[@]}"; do
    exp=$(grep -w "^#& $user" "/etc/xray/config.json" | cut -d ' ' -f 3 | sort | uniq)
    d1=$(date -d "$exp" +%s)
    d2=$(date -d "$now" +%s)
    exp2=$(((d1 - d2) / 86400))
    if [[ "$exp2" -le "0" ]]; then
        uuid=$(grep -E "^},{" "/etc/xray/config.json" | grep -wE '"'"${user}"'"' | cut -d " " -f 2 | cut -d '"' -f 2 | uniq)
        sed -i '/#vless$/a\#& '"$user $exp $uuid"'' /etc/xray/.lock.db
        sed -i "/^#& $user/,/^},{/d" /etc/xray/config.json
        sed -i "/^#&& $user/,/^},{/d" /etc/xray/config.json
        systemctl restart xray > /dev/null 2>&1
        echo "[VLESS] 🔒 $user expired on $exp"
        locked_accounts[vless]+=("$user")
    fi
done

#----- Auto Lock Trojan
data=($(cat /etc/xray/config.json | grep '^#!' | cut -d ' ' -f 2 | sort | uniq))
for user in "${data[@]}"; do
    exp=$(grep -w "^#! $user" "/etc/xray/config.json" | cut -d ' ' -f 3 | sort | uniq)
    d1=$(date -d "$exp" +%s)
    d2=$(date -d "$now" +%s)
    exp2=$(((d1 - d2) / 86400))
    if [[ "$exp2" -le "0" ]]; then
        uuid=$(grep -E "^},{" "/etc/xray/config.json" | grep -wE '"'"${user}"'"' | cut -d " " -f 2 | cut -d '"' -f 2 | uniq)
        sed -i '/#trojan$/a\#! '"$user $exp $uuid"'' /etc/xray/.lock.db
        sed -i "/^#! $user/,/^},{/d" /etc/xray/config.json
        sed -i "/^#!# $user/,/^},{/d" /etc/xray/config.json
        systemctl restart xray > /dev/null 2>&1
        echo "[TROJAN] 🔒 $user expired on $exp"
        locked_accounts[trojan]+=("$user")
    fi
done

#----- Auto Lock Shadowsocks
data=($(cat /etc/xray/config.json | grep '^#!!' | cut -d ' ' -f 2 | sort | uniq))
for user in "${data[@]}"; do
    exp=$(grep -w "^#!! $user" "/etc/xray/config.json" | cut -d ' ' -f 3 | sort | uniq)
    d1=$(date -d "$exp" +%s)
    d2=$(date -d "$now" +%s)
    exp2=$(((d1 - d2) / 86400))
    if [[ "$exp2" -le "0" ]]; then
        uuid=$(grep -E "^},{" "/etc/xray/config.json" | grep -wE '"'"${user}"'"' | cut -d " " -f 2 | cut -d '"' -f 2 | uniq)
        sed -i '/#ss$/a\#!! '"$user $exp $uuid"'' /etc/xray/.lock.db
        sed -i "/^#!! $user/,/^},{/d" /etc/xray/config.json
        sed -i "/^#&! $user/,/^},{/d" /etc/xray/config.json
        systemctl restart xray > /dev/null 2>&1
        echo "[SHADOWSOCKS] 🔒 $user expired on $exp"
        locked_accounts[shadowsocks]+=("$user")
    fi
done

#----- Auto Lock SSH (skip already locked accounts)
hariini=$(date +%d-%m-%Y)
cat /etc/shadow | cut -d: -f1,2,8 | grep -v '!\|*' | cut -d: -f1,8 > /tmp/expirelist.txt
totalaccounts=$(cat /tmp/expirelist.txt | wc -l)
for ((i = 1; i <= $totalaccounts; i++)); do
    tuserval=$(head -n $i /tmp/expirelist.txt | tail -n 1)
    username=$(echo $tuserval | cut -f1 -d:)
    userexp=$(echo $tuserval | cut -f2 -d:)
    
    # Skip if account is already locked
    if passwd -S "$username" 2>/dev/null | grep -q "locked"; then
        echo "[SSH] ⏩ $username is already locked (skipped)"
        continue
    fi
    
    userexpireinseconds=$(($userexp * 86400))
    tglexp=$(date -d @$userexpireinseconds)
    bulantahun=$(echo $tglexp | awk -F" " '{print $2,$6}')
    todaystime=$(date +%s)
    
    if [ $userexpireinseconds -ge $todaystime ]; then
        :
    else
        passwd -l $username > /dev/null 2>&1
        echo "[SSH] 🔒 $username expired on $bulantahun"
        locked_accounts[ssh]+=("$username")
    fi
done

# Send notifications for each protocol
for protocol in "${!locked_accounts[@]}"; do
    send_notification "$protocol" locked_accounts[$protocol]
done

systemctl restart xray
systemctl reload sshd  
