#!/usr/bin/env python3
import json
import os
import re
import subprocess
from datetime import datetime
import requests
from pathlib import Path

class AccountLocker:
    def __init__(self):
        self.now = datetime.now().strftime("%Y-%m-%d")
        self.myip = self.get_public_ip()
        self.locked_accounts = {
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
            # Read bot configuration
            with open("/etc/bot/.bot.db") as f:
                for line in f:
                    if line.startswith("#bot#"):
                        parts = line.strip().split()
                        if len(parts) >= 4:
                            key = parts[2]
                            chat_id = parts[3]
                            break
                else:
                    print("Telegram bot config not found or invalid")
                    return
                    
            url = f"https://api.telegram.org/bot{key}/sendMessage"
            html_message = self.format_html_message(protocol, accounts)
            
            response = requests.post(
                url,
                data={
                    "chat_id": chat_id,
                    "text": html_message,
                    "parse_mode": "html",
                    "disable_web_page_preview": "true"
                },
                timeout=10
            )
            response.raise_for_status()
        except Exception as e:
            print(f"Failed to send Telegram notification: {e}")
    
    def lock_xray_account(self, protocol, user, exp, uuid):
        try:
            # Add to lock database
            lock_entry = {
                "vmess": f"### {user} {exp} {uuid}",
                "vless": f"#& {user} {exp} {uuid}",
                "trojan": f"#! {user} {exp} {uuid}",
                "shadowsocks": f"#!! {user} {exp} {uuid}"
            }[protocol]
            
            with open("/etc/xray/.lock.db", "a") as f:
                f.write(f"{lock_entry}\n")
            
            # Remove from config
            self.remove_from_xray_config(protocol, user)
            
            print(f"[{protocol.upper()}] 🔒 {user} expired on {exp}")
            self.locked_accounts[protocol].append(user)
            return True
        except Exception as e:
            print(f"Error locking {protocol} account {user}: {e}")
            return False
    
    def remove_from_xray_config(self, protocol, user):
        try:
            # This is a simplified version - actual implementation needs to handle JSON properly
            config_file = "/etc/xray/config.json"
            with open(config_file) as f:
                config = json.load(f)
            
            # Implement actual removal logic based on protocol patterns
            # This needs to be adapted to your actual config.json structure
            
            # Save modified config
            with open(config_file, "w") as f:
                json.dump(config, f, indent=2)
                
        except Exception as e:
            print(f"Error removing {user} from Xray config: {e}")
    
    def lock_ssh_account(self, username):
        try:
            # Skip root account
            if username == "root":
                print("[SSH] ⏩ root skipped (root account)")
                return False
                
            # Check if already locked
            result = subprocess.run(["passwd", "-S", username], 
                                  capture_output=True, text=True)
            if "locked" in result.stdout:
                print(f"[SSH] ⏩ {username} skipped (already locked)")
                return False
                
            # Lock the account
            subprocess.run(["passwd", "-l", username], check=True)
            print(f"[SSH] 🔒 {username} locked")
            self.locked_accounts["ssh"].append(username)
            return True
        except subprocess.CalledProcessError as e:
            print(f"Failed to lock SSH account {username}: {e}")
            return False
    
    def check_xray_accounts(self):
        try:
            with open("/etc/xray/config.json") as f:
                config = f.read()
            
            # Check VMESS accounts
            for match in re.finditer(r'^### (\S+) (\S+)', config, re.M):
                user, exp = match.groups()
                if self.is_expired(exp):
                    uuid = self.find_uuid(config, user)
                    if uuid:
                        self.lock_xray_account("vmess", user, exp, uuid)
            
            # Check VLESS accounts (similar pattern)
            # Check TROJAN accounts
            # Check SHADOWSOCKS accounts
            
        except Exception as e:
            print(f"Error checking Xray accounts: {e}")
    
    def find_uuid(self, config, user):
        # Find UUID for the user in config
        match = re.search(fr'"email":\s*"{user}".*?"id":\s*"([^"]+)"', config)
        return match.group(1) if match else None
    
    def is_expired(self, exp_date):
        try:
            exp = datetime.strptime(exp_date, "%Y-%m-%d")
            now = datetime.strptime(self.now, "%Y-%m-%d")
            return (exp - now).days <= 0
        except:
            return False
    
    def check_ssh_accounts(self):
        try:
            with open("/etc/passwd") as f:
                for line in f:
                    if line.startswith("root:") or line.startswith("*:"):
                        continue
                        
                    parts = line.strip().split(":")
                    if len(parts) < 8:
                        continue
                        
                    username = parts[0]
                    exp = parts[7]
                    
                    if exp and exp.isdigit():
                        if self.is_ssh_expired(int(exp)):
                            self.lock_ssh_account(username)
        except Exception as e:
            print(f"Error checking SSH accounts: {e}")
    
    def is_ssh_expired(self, exp_days):
        exp_seconds = exp_days * 86400
        current_seconds = int(datetime.now().timestamp())
        return exp_seconds <= current_seconds
    
    def restart_services(self):
        try:
            subprocess.run(["systemctl", "restart", "xray"], check=True)
            subprocess.run(["systemctl", "reload", "sshd"], check=True)
        except subprocess.CalledProcessError as e:
            print(f"Failed to restart services: {e}")
    
    def run(self):
        print(f"Starting account lock process at {self.now}")
        
        # Check and lock Xray accounts
        self.check_xray_accounts()
        
        # Check and lock SSH accounts
        self.check_ssh_accounts()
        
        # Send notifications
        for protocol, accounts in self.locked_accounts.items():
            if accounts:
                self.send_telegram_notification(protocol, accounts)
        
        # Restart services
        self.restart_services()
        
        print("Account lock process completed")

if __name__ == "__main__":
    locker = AccountLocker()
    locker.run()