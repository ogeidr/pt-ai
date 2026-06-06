#!/usr/bin/env bash
# 04-harden.sh: Re-assert SSH/account hardening and enable security updates.
# Runs on every `vagrant up`; idempotent. Catches the case where the box
# wasn't built by box/build.sh (e.g. the official kalilinux/rolling box on
# Intel Mac / Linux) and ensures both paths land in the same hardened state.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
# shellcheck source=/dev/null
. /vagrant/provision/_lib.sh

# --- SSH ------------------------------------------------------------------
# Key auth only; no password fallback; no root login.
sed -i \
    -e 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' \
    -e 's/^#*KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' \
    -e 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' \
    -e 's/^#*PermitRootLogin.*/PermitRootLogin no/' \
    -e 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords no/' \
    /etc/ssh/sshd_config

# Restart only if something changed; sshd_config -t catches sed mistakes.
sshd -t
systemctl reload ssh

# --- Vagrant account ------------------------------------------------------
# Lock the password — key auth + NOPASSWD sudo cover all legitimate access.
# `passwd -l` is idempotent (re-locking a locked account is a no-op).
passwd -l vagrant >/dev/null

# --- Unattended security updates -----------------------------------------
# Security-only, no auto-reboot. Drops the burden of "did you patch?" while
# keeping engagements deterministic (no random feature upgrades).
if $IS_APT; then
    apt-get update -y
    apt-get install -y --no-install-recommends unattended-upgrades

    # The origins pattern is distro-specific. On Kali, pin it to the Kali
    # archive; on other apt boxes keep the package's own default origins
    # (Debian/Ubuntu ship a working 50unattended-upgrades out of the box).
    if $IS_KALI; then
        cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Origins-Pattern {
    "origin=Kali,codename=${distro_codename},label=Kali";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "false";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
    fi

    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

    systemctl enable --now unattended-upgrades >/dev/null
else
    echo "[04-harden] non-apt distro — skipping unattended-upgrades" >&2
fi
