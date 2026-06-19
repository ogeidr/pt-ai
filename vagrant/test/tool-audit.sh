#!/usr/bin/env bash
# tool-audit.sh — report which tools the pt-ai agents/skills reference that are
# MISSING on the current box. Read-only; installs nothing. Run inside a guest:
#   bash /vagrant/test/tool-audit.sh
# (vagrant syncs vagrant/ -> /vagrant, so this file is present in every guest.)
#
# Goal: a per-box "missing tools" list, so the same harness can be compared
# across Kali (kali-linux-default present) and Debian (framework layer only).
set -u

# Load the provisioned env so pipx/npm/ghidra CLIs are on PATH under non-login ssh.
[ -r /etc/profile.d/pt-ai.sh ]            && . /etc/profile.d/pt-ai.sh
[ -r /etc/profile.d/pt-ai-ghidrasql.sh ]  && . /etc/profile.d/pt-ai-ghidrasql.sh
[ -r /etc/profile.d/pt-ai-ghidra-rpc.sh ] && . /etc/profile.d/pt-ai-ghidra-rpc.sh
export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:/usr/local/bin:/usr/sbin:/sbin:$PATH"

ID=""; [ -r /etc/os-release ] && . /etc/os-release
echo "== pt-ai tool audit on: ${PRETTY_NAME:-unknown} (ID=${ID:-?}) =="

# Tool groups -> the agent/skill area that needs them. "name:binary" when the
# binary differs from the package/common name.
groups="
recon-skill(full-recon): nmap masscan dig whois curl whatweb nikto nc
web/recon(agents):        ffuf gobuster feroxbuster dirb sqlmap nuclei amass subfinder httpx dnsenum dnsrecon theharvester
ad(agents):               crackmapexec netexec evil-winrm responder ldapsearch kerbrute certipy-ad bloodhound smbclient smbmap rpcclient enum4linux-ng
impacket(agents):         impacket-GetUserSPNs impacket-GetNPUsers impacket-secretsdump
creds(agents):            hydra medusa john hashcat
cloud(skills+agents):     aws az gcloud pacu prowler scout trufflehog gitleaks
k8s(k8s-recon skill):     kubectl kube-hunter kubeaudit trivy
mobile(agents):           frida objection apktool jadx
wireless(agents):         aircrack-ng bettercap reaver hostapd wifite
reverse-eng(agents+skills): radare2 ghidrasql ghidra-rpc binwalk strings
exploit/web(agents):      msfconsole burpsuite
"

# Iterate group lines; first field (before ':') is the label, rest are tools.
printf '%s\n' "$groups" | while IFS= read -r line; do
    [ -z "$line" ] && continue
    label=${line%%:*}
    tools=${line#*:}
    missing=""
    for t in $tools; do
        command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
    done
    if [ -n "$missing" ]; then
        printf '  [%s]\n    MISSING:%s\n' "$label" "$missing"
    else
        printf '  [%s]  all present\n' "$label"
    fi
done

echo
echo "Note: seclists -> /usr/share/seclists ; impacket via impacket-scripts package."
[ -d /usr/share/seclists ] && echo "  seclists present" || echo "  MISSING: seclists (/usr/share/seclists)"
