#!/bin/bash
now=$(date +"%Y-%m-%d")
MYIP=$(curl -sS ipinfo.io/ip)
clear

# Initialize locked accounts as associative arrays
declare -A locked_accounts=(
    [vmess]=()
    [vless]=()
    [trojan]=()
    [shadowsocks]=()
    [ssh]=()
)

function format_html_message() {
    local protocol=$1
    local accounts=($2)
    
    [[ ${#accounts[@]} -eq 0 ]] && return

    local message="
<html>
<body>
<pre style=\"font-family: monospace;\">
──────────────────────────
<b>⚠️ NOTIF EXP ${protocol^^} LOCKED ⚠️</b>
──────────────────────────
<b>🔒 Total locked: ${#accounts[@]}</b>
<b>📅 Date: $now</b>
──────────────────────────
"
    for account in "${accounts[@]}"; do
        message+="🔐 $(printf "%-25s" "$account")\n"
    done
    
    message+="──────────────────────────
</pre>
</body>
</html>"
    
    echo "$message"
}

function send_telegram_notification() {
    local protocol=$1
    shift
    local accounts=("$@")
    
    [[ ${#accounts[@]} -eq 0 ]] && return

    local CHATID=$(awk '/^#bot# / {print $3}' /etc/bot/.bot.db)
    local KEY=$(awk '/^#bot# / {print $2}' /etc/bot/.bot.db)
    local URL="https://api.telegram.org/bot$KEY/sendMessage"
    
    local html_message=$(format_html_message "$protocol" "${accounts[*]}")
    
    curl -sS --max-time 10 \
        -X POST "$URL" \
        -d chat_id="$CHATID" \
        -d text="$html_message" \
        -d parse_mode="html" \
        -d disable_web_page_preview="true" >/dev/null
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

#----- Auto Lock SSH (with root protection)
hariini=$(date +%d-%m-%Y)
while IFS=: read -r username _ _ _ _ _ _ exp; do
    # Skip root account and already locked accounts
    if [[ "$username" == "root" ]]; then
        echo "[SSH] ⏩ $username skipped (root account)"
        continue
    fi
    
    # Check if account is already locked
    if passwd -S "$username" 2>/dev/null | grep -q "locked"; then
        echo "[SSH] ⏩ $username skipped (already locked)"
        continue
    fi
    
    # Check expiration
    if [[ "$exp" -ne "" && "$exp" -le $(($(date +%s)/86400)) ]]; then
        passwd -l "$username" >/dev/null 2>&1
        exp_date=$(date -d "@$((exp * 86400))" "+%d-%m-%Y")
        echo "[SSH] 🔒 $username expired on $exp_date"
        locked_accounts[ssh]+=("$username")
    fi
done < <(grep -vE '^root:|^\*:' /etc/passwd | awk -F: '{print $1,$8}')

# Send notifications
for protocol in "${!locked_accounts[@]}"; do
    if [[ ${#locked_accounts[$protocol][@]} -gt 0 ]]; then
        send_telegram_notification "$protocol" "${locked_accounts[$protocol][@]}"
    fi
done

systemctl restart xray >/dev/null 2>&1
systemctl reload sshd >/dev/null 2>&1