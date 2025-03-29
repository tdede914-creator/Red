#!/usr/bin/env python3
import json
import os
import re
import subprocess
from datetime import datetime
import requests
from pathlib import Path

class AccountCleaner:
    def __init__(self):
        self.now = datetime.now().strftime("%Y-%m-%d")
        self.myip = self.get_public_ip()
        self.expired_accounts = {
            "vmess": [],
            "vless": [],
            "trojan": [],
            "shadowsocks": [],
            "ssh": []
        }
        
    def get_public_ip(self):
        try:
            return requests.get('https://ipinfo.io/ip', timeout=5).text.strip()
        except:
            return "IP_UNKNOWN"
    
    def format_html_message(self, protocol, accounts):
        if not accounts:
            return ""
            
        message = f"""
<html>
<body>
<pre style="font-family: monospace;">
──────────────────────────
<b>⚠️ NOTIF EXP {protocol.upper()} LOCKED ⚠️</b>
──────────────────────────
<b>🔒 Total locked: {len(accounts)}</b>
<b>📅 Date: {self.now}</b>
──────────────────────────
"""
        for account in accounts:
            message += f"🔐 {account.ljust(25)}\n"
        
        message += "──────────────────────────\n</pre>\n</body>\n</html>"
        return message
    
    def send_telegram_notification(self, protocol, accounts):
        if not accounts:
            return
            
        try:
            with open("/etc/bot/.bot.db") as f:
                for line in f:
                    if line.startswith("#bot#"):
                        parts = line.strip().split()
                        key = parts[2]
                        chat_id = parts[3]
                        break
                else:
                    print("Telegram bot config not found")
                    return
                    
            url = f"https://api.telegram.org/bot{key}/sendMessage"
            html_message = self.format_html_message(protocol, accounts)
            
            requests.post(
                url,
                data={
                    "chat_id": chat_id,
                    "text": html_message,
                    "parse_mode": "html",
                    "disable_web_page_preview": "true"
                },
                timeout=10
            )
        except Exception as e:
            print(f"Failed to send Telegram notification: {e}")
    
    def clean_xray_accounts(self, protocol, pattern, db_path, config_paths):
        try:
            with open("/etc/xray/config.json") as f:
                config = json.load(f)
                
            users = set()
            # Find all users matching the pattern
            for inbound in config.get("inbounds", []):
                for client in inbound.get("settings", {}).get("clients", []):
                    if "email" in client:
                        users.add(client["email"])
            
            # Process expiration
            for user in users:
                # This part needs adjustment based on your actual config.json structure
                # The original script used grep patterns which would need to be translated
                # to proper JSON traversal
                exp_date = "..."  # Extract expiration from config
                
                if self.is_expired(exp_date):
                    self.remove_account_files(protocol, user)
                    self.expired_accounts[protocol].append(user)
                    print(f"[{protocol.upper()}] 🗑️ {user} expired on {exp_date}")
                    
        except Exception as e:
            print(f"Error processing {protocol} accounts: {e}")
    
    def clean_ssh_accounts(self):
        try:
            with open("/etc/passwd") as f:
                for line in f:
                    if line.startswith("root:"):
                        continue
                        
                    parts = line.strip().split(":")
                    username = parts[0]
                    exp_days = parts[7] if len(parts) > 7 else None
                    
                    if not exp_days or not exp_days.isdigit():
                        continue
                        
                    if self.is_ssh_expired(int(exp_days)):
                        self.remove_ssh_account(username)
                        self.expired_accounts["ssh"].append(username)
                        
        except Exception as e:
            print(f"Error processing SSH accounts: {e}")
    
    def is_expired(self, exp_date):
        try:
            exp = datetime.strptime(exp_date, "%Y-%m-%d")
            now = datetime.strptime(self.now, "%Y-%m-%d")
            return (exp - now).days <= 0
        except:
            return False
    
    def is_ssh_expired(self, exp_days):
        exp_seconds = exp_days * 86400
        current_seconds = int(datetime.now().timestamp())
        return exp_seconds <= current_seconds
    
    def remove_account_files(self, protocol, username):
        try:
            paths = {
                "vmess": [
                    f"/etc/vmess/{username}",
                    f"/etc/kyt/limit/vmess/ip/{username}",
                    f"/etc/limit/vmess/{username}",
                    f"/var/www/html/vmess-{username}.txt"
                ],
                "vless": [
                    f"/etc/vless/{username}",
                    f"/etc/kyt/limit/vless/ip/{username}",
                    f"/etc/limit/vless/{username}",
                    f"/var/www/html/vless-{username}.txt"
                ],
                "trojan": [
                    f"/etc/trojan/{username}",
                    f"/etc/kyt/limit/trojan/ip/{username}",
                    f"/etc/limit/trojan/{username}",
                    f"/var/www/html/trojan-{username}.txt"
                ],
                "shadowsocks": [
                    f"/etc/shadowsocks/{username}",
                    f"/etc/kyt/limit/shadowsocks/ip/{username}",
                    f"/etc/limit/shadowsocks/{username}",
                    f"/var/www/html/shadowsocks-{username}.txt"
                ]
            }
            
            for path in paths.get(protocol, []):
                try:
                    if os.path.isfile(path):
                        os.unlink(path)
                    elif os.path.isdir(path):
                        subprocess.run(["rm", "-rf", path], check=True)
                except Exception as e:
                    print(f"Failed to remove {path}: {e}")
                    
        except Exception as e:
            print(f"Error removing {protocol} account files: {e}")
    
    def remove_ssh_account(self, username):
        try:
            subprocess.run(["userdel", "--force", username], check=True)
            
            # Remove SSH-related files
            ssh_files = [
                f"/etc/ssh/{username}",
                f"/etc/kyt/limit/ssh/ip/{username}",
                f"/var/www/html/ssh-{username}.txt"
            ]
            
            for path in ssh_files:
                try:
                    if os.path.exists(path):
                        os.unlink(path)
                except Exception as e:
                    print(f"Failed to remove SSH file {path}: {e}")
                    
        except subprocess.CalledProcessError as e:
            print(f"Failed to remove SSH user {username}: {e}")
    
    def restart_services(self):
        try:
            subprocess.run(["systemctl", "restart", "xray"], check=True)
            subprocess.run(["systemctl", "reload", "sshd"], check=True)
        except subprocess.CalledProcessError as e:
            print(f"Failed to restart services: {e}")
    
    def run(self):
        # Clean Xray accounts
        self.clean_xray_accounts("vmess", "^###", "/etc/vmess/.vmess.db", ["/etc/xray/config.json"])
        self.clean_xray_accounts("vless", "^#&", "/etc/vless/.vless.db", ["/etc/xray/config.json"])
        self.clean_xray_accounts("trojan", "^#!", "/etc/trojan/.trojan.db", ["/etc/xray/config.json"])
        self.clean_xray_accounts("shadowsocks", "^#!!", "/etc/shadowsocks/.shadowsocks.db", ["/etc/xray/config.json"])
        
        # Clean SSH accounts
        self.clean_ssh_accounts()
        
        # Send notifications
        for protocol, accounts in self.expired_accounts.items():
            if accounts:
                self.send_telegram_notification(protocol, accounts)
        
        # Restart services
        self.restart_services()

if __name__ == "__main__":
    cleaner = AccountCleaner()
    cleaner.run()