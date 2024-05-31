#!/bin/bash
Green_font_prefix="\033[32m" && Red_font_prefix="\033[31m" && Green_background_prefix="\033[42;37m" && Red_background_prefix="\033[41;37m" && Font_color_suffix="\033[0m"
Info="${Green_font_prefix}[ON]${Font_color_suffix}"
Error="${Red_font_prefix}[OFF]${Font_color_suffix}"
cek=$(grep -c -E "^# BEGIN_REBOOT" /etc/crontab)
if [[ "$cek" = "1" ]]; then
sts="${Info}"
else
sts="${Error}"
fi
clear
echo -e ""
echo -e "\033[1;93m┌──────────────────────────────────────────┐\033[0m"
echo -e "\033[1;93m│  AUTO REBOOT $sts          " |lolcat
echo -e "\033[1;93m└──────────────────────────────────────────┘\033[0m"
echo -e "\033[1;93m┌──────────────────────────────────────────┐\033[0m"
echo -e "\033[1;93m│  1.AUTO REBOOT$"|lolcat
echo -e "\033[1;93m│  2.OFF AUTO REBOOT"|lolcat
echo -e "\033[1;93m│  0.BACK TO EXIT MENU \033[1;32m<\033[1;33m<\033[1;31m<\033[1;31m$NC \E[0m\033[0;34m "
echo -e "\033[1;93m└──────────────────────────────────────────┘\033[0m"
echo -e ""
read -p " Select menu : " opt
echo -e ""
case $opt in
1 | 01)
clear
sed -i "/^# BEGIN_REBOOT/,/^# REBOOT/d" /etc/crontab
cat << EOF >> /etc/crontab
# BEGIN_REBOOT
10 */12 * * * root fixcert
0 0 * * * root reboot
# END_REBOOT
EOF
service cron restart
sleep 1
echo -e "Auto-REBOOT Sucsesfully"
echo -e "\033[1;93m======================================\033[0m"
read -n 1 -s -r -p "Press any key to back on menu"
auto-reboot
;;
2 | 02)
clear
sed -i "/^# BEGIN_REBOOT/,/^# END_REBOOT/d" /etc/crontab
echo -e "OFF Auto-REBOOT Sucsesfully"
echo -e "\033[1;93m======================================\033[0m"
read -n 1 -s -r -p "Press any key to back on menu"
auto-reboot
;;
0 | 00)
clear
menu
;;
x)
exit
;;
esac
