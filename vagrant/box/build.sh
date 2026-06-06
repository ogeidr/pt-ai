#!/usr/bin/env bash
# box/build.sh: Build a kali-arm64 Vagrant box from the official Kali ARM64 ISO.
#
# Flow:
#   1. Downloads the latest Kali ARM64 installer ISO from kali.org (auto-detected)
#   2. Creates a VMware Fusion VM (vmx + vmdk)
#   3. Boots the VM — you install Kali via the GUI (~20 min)
#   4. Configures the installed VM as a Vagrant base box via SSH
#   5. Packages and registers it locally as 'kali-arm64'
#
# Prerequisites: curl, vagrant, VMware Fusion 13+, vagrant-vmware-desktop plugin
#
# Platform: macOS only. This builds an ARM64 box for Apple Silicon, which is
# the one case with no official Kali VMware box. Intel Mac and Linux users do
# not need this script — the default VirtualBox setup uses the official
# kalilinux/rolling box and is fully cross-platform.
#
# Usage: ./box/build.sh
set -euo pipefail

err() { echo "Error: $*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || err "box/build.sh runs only on macOS with VMware Fusion.
On Intel Mac or Linux you don't need it — use the default VirtualBox setup
(box defaults to kalilinux/rolling; override with PTAI_BOX). See README.md."

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
WORK_DIR="$SCRIPT_DIR/.build"
BOX_NAME="kali-arm64"
BOX_FILE="$SCRIPT_DIR/kali-arm64.box"
VM_NAME="kali-ptai-build"
VM_DIR="$WORK_DIR/$VM_NAME"
VMX_FILE="$VM_DIR/$VM_NAME.vmx"
VMDK_FILE="$VM_DIR/$VM_NAME.vmdk"
ISO_BASE_URL="https://kali.download/base-images/current"

VMRUN="$( find '/Applications/VMware Fusion.app' -name vmrun -type f 2>/dev/null | head -1 )"
VDISKMANAGER="$( find '/Applications/VMware Fusion.app' -name vmware-vdiskmanager -type f 2>/dev/null | head -1 )"

info() { echo "==> $*" >&2; }

check_deps() {
    for cmd in curl shasum vagrant; do
        command -v "$cmd" >/dev/null 2>&1 || err "$cmd not found"
    done
    [ -n "$VMRUN" ]        || err "vmrun not found — is VMware Fusion installed?"
    [ -n "$VDISKMANAGER" ] || err "vmware-vdiskmanager not found — is VMware Fusion installed?"
}

detect_iso_url() {
    info "Detecting latest Kali ARM64 ISO..."
    local filename
    filename=$(curl -s "$ISO_BASE_URL/SHA256SUMS" \
        | grep -oE 'kali-linux-[0-9.]+-installer-arm64\.iso' \
        | head -1 \
        | tr -d '\r')
    [ -n "$filename" ] || err "Could not find installer-arm64.iso in $ISO_BASE_URL/SHA256SUMS"
    echo "$ISO_BASE_URL/$filename"
}

download_iso() {
    local url="$1"
    local dest="$WORK_DIR/$(basename "$url")"
    mkdir -p "$WORK_DIR"
    if [ -f "$dest" ]; then
        info "ISO already present: $dest"
    else
        info "Downloading $(basename "$url") ..."
        curl -L --progress-bar -o "$dest" "$url"
    fi

    info "Verifying checksum..."
    local expected actual
    expected=$(curl -s "$ISO_BASE_URL/SHA256SUMS" \
        | tr -d '\r' \
        | grep " $(basename "$dest")$" \
        | awk '{print $1}')
    if [ -n "$expected" ]; then
        actual=$(shasum -a 256 "$dest" | awk '{print $1}')
        if [ "$expected" != "$actual" ]; then
            rm -f "$dest"
            err "Checksum mismatch — corrupt download removed, re-run to retry"
        fi
        info "Checksum OK"
    else
        info "Warning: could not fetch expected checksum; skipping verification"
    fi
    echo "$dest"
}

create_vm() {
    local iso="$1"
    if [ -f "$VMX_FILE" ]; then
        info "VM already exists: $VMX_FILE"
        return
    fi
    mkdir -p "$VM_DIR"

    info "Creating 40 GB virtual disk..."
    "$VDISKMANAGER" -c -s 40GB -a ide -t 0 "$VMDK_FILE"

    info "Writing VMX config..."
    cat > "$VMX_FILE" <<EOF
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "21"
firmware = "efi"
guestOS = "arm-ubuntu-64"
displayName = "$VM_NAME"
memsize = "4096"
numvcpus = "4"
pciBridge0.present = "TRUE"
pciBridge4.present = "TRUE"
pciBridge4.virtualDev = "pcieRootPort"
pciBridge4.functions = "8"
pciBridge5.present = "TRUE"
pciBridge5.virtualDev = "pcieRootPort"
pciBridge5.functions = "8"
pciBridge6.present = "TRUE"
pciBridge6.virtualDev = "pcieRootPort"
pciBridge6.functions = "8"
pciBridge7.present = "TRUE"
pciBridge7.virtualDev = "pcieRootPort"
pciBridge7.functions = "8"
sata0.present = "TRUE"
sata0:0.present = "TRUE"
sata0:0.fileName = "$VM_NAME.vmdk"
sata0:1.present = "TRUE"
sata0:1.fileName = "$iso"
sata0:1.deviceType = "cdrom-image"
ethernet0.present = "TRUE"
ethernet0.connectionType = "nat"
ethernet0.virtualDev = "vmxnet3"
ethernet0.addressType = "generated"
usb.present = "TRUE"
usb_xhci.present = "TRUE"
sound.present = "FALSE"
EOF
}

boot_for_install() {
    info "Starting VM in VMware Fusion..."
    open -a "VMware Fusion" "$VMX_FILE"

    cat <<'EOF'

================================================================================
  Install Kali in the VMware Fusion window that just opened.
  Follow these settings exactly so the post-install config works:
--------------------------------------------------------------------------------
  Hostname  : kali-ptai          Domain: (leave blank)
  Full name : vagrant            Username: vagrant       Password: vagrant
  Partition : Guided - use entire disk -> all files in one partition
  Software  : keep defaults — make sure "SSH server" is included
               also select / install:  open-vm-tools
  GRUB      : install to the primary EFI partition

  After the installer reboots into Kali, log in as vagrant and run:

    sudo systemctl enable --now ssh

  Then come back here.
================================================================================

EOF
    printf "Press Enter once Kali is installed, running, and SSH is up: "
    read -r _
}

get_vm_ip() {
    info "Detecting VM IP (requires open-vm-tools in the guest)..."
    local ip
    ip=$("$VMRUN" -T fusion getGuestIPAddress "$VMX_FILE" -wait 2>/dev/null || true)
    if [ -z "$ip" ]; then
        printf "Auto-detect failed. Enter the VM IP (run 'ip a' in the VM): "
        read -r ip
    fi
    [ -n "$ip" ] || err "No IP address provided"
    echo "$ip"
}

configure_for_vagrant() {
    local ip="$1"
    info "Configuring VM as Vagrant base box (vagrant@$ip)..."
    info "You will be prompted for the VM password once — type: vagrant"

    local ctl="$WORK_DIR/ssh-ctl"
    local ssh_base=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=15)
    local ssh_ctl=(-o ControlPath="$ctl" "${ssh_base[@]}")

    # Remove stale control socket from any previous failed run
    rm -f "$ctl"

    # Establish master connection — user types password once here
    ssh -fNM "${ssh_ctl[@]}" -o ControlPersist=300s vagrant@"$ip"

    # Bootstrap passwordless sudo.
    # -tt satisfies Kali's requiretty sudoers default;
    # echo pipe feeds the password to sudo -S without a second prompt.
    # Re-establish master after -tt closes it (force-TTY tears down multiplexing).
    info "Bootstrapping passwordless sudo..."
    ssh -tt "${ssh_base[@]}" vagrant@"$ip" \
        "echo 'vagrant' | sudo -S sh -c 'echo \"vagrant ALL=(ALL) NOPASSWD: ALL\" > /etc/sudoers.d/vagrant && chmod 440 /etc/sudoers.d/vagrant'"
    ssh -fNM "${ssh_ctl[@]}" -o ControlPersist=300s vagrant@"$ip"

    # Remaining config with passwordless sudo — no TTY needed
    info "Running post-install configuration (hardening + cleanup)..."
    ssh "${ssh_ctl[@]}" vagrant@"$ip" "sudo bash -s" <<'ENDSSH'
set -e

# --- SSH hardening --------------------------------------------------------
# Install Vagrant's well-known insecure public key so Vagrant can key-auth
# on first `vagrant up`. Vagrant detects this key and automatically swaps it
# for a freshly-generated unique key, then removes the insecure one.
install -d -m 700 -o vagrant -g vagrant /home/vagrant/.ssh
cat > /home/vagrant/.ssh/authorized_keys <<'KEY'
ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzIw+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoPkcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NOTd0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcWyLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQ== vagrant insecure public key
KEY
chown vagrant:vagrant /home/vagrant/.ssh/authorized_keys
chmod 600 /home/vagrant/.ssh/authorized_keys

# Lock the vagrant password — key auth + NOPASSWD sudo cover all needs.
# This blocks both SSH password login and VMware console login for vagrant.
passwd -l vagrant

# Disable password / keyboard-interactive SSH. Only key auth from here on.
sed -i \
    -e 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' \
    -e 's/^#*KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' \
    -e 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' \
    -e 's/^#*PermitRootLogin.*/PermitRootLogin no/' \
    /etc/ssh/sshd_config
systemctl restart ssh

# --- Base packages --------------------------------------------------------
apt-get install -y --no-install-recommends open-vm-tools

# --- Cleanup --------------------------------------------------------------
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -f /etc/udev/rules.d/70-persistent-net.rules
find /var/log -type f -writable -exec truncate -s 0 {} + 2>/dev/null || true
dd if=/dev/zero of=/tmp/zero bs=1M 2>/dev/null || true; rm -f /tmp/zero
ENDSSH

    ssh -O exit "${ssh_ctl[@]}" vagrant@"$ip" 2>/dev/null || true
    info "Guest configuration done"
}

package_box() {
    info "Shutting down VM..."
    "$VMRUN" -T fusion stop "$VMX_FILE" soft 2>/dev/null \
        || "$VMRUN" -T fusion stop "$VMX_FILE" hard 2>/dev/null || true
    sleep 3

    local pkg_dir="$WORK_DIR/box-pkg"
    mkdir -p "$pkg_dir"

    # No ssh.password — the box ships with Vagrant's insecure public key
    # in authorized_keys; Vagrant key-auths on first up and swaps it for a
    # generated unique key. Password auth is disabled in sshd_config.
    cat > "$pkg_dir/Vagrantfile" <<'EOF'
Vagrant.configure("2") do |config|
  config.ssh.username = "vagrant"
end
EOF

    cat > "$pkg_dir/metadata.json" <<'EOF'
{"provider":"vmware_desktop"}
EOF

    # Normalise paths in VMX to relative so the box is portable.
    # BSD sed (macOS) — the '' is the mandatory in-place backup-suffix arg.
    # Correct as-is: this script is macOS-only (guarded at the top).
    sed -i '' \
        -e "s|$VM_DIR/||g" \
        -e 's|sata0:1\.fileName = ".*"|sata0:1.fileName = ""|' \
        "$VMX_FILE"

    cp "$VM_DIR"/*.vmx   "$pkg_dir/" 2>/dev/null || true
    cp "$VM_DIR"/*.vmdk  "$pkg_dir/" 2>/dev/null || true
    cp "$VM_DIR"/*.nvram "$pkg_dir/" 2>/dev/null || true

    info "Packaging box (this will take a few minutes)..."
    tar -czf "$BOX_FILE" -C "$pkg_dir" .
    info "Box created: $BOX_FILE"
}

# ---------------------------------------------------------------------------

check_deps
mkdir -p "$WORK_DIR"

ISO_URL=$(detect_iso_url)
ISO=$(download_iso "$ISO_URL")

create_vm "$ISO"
boot_for_install

VM_IP=$(get_vm_ip)
configure_for_vagrant "$VM_IP"
package_box

info "Registering box as '$BOX_NAME'..."
vagrant box remove "$BOX_NAME" --provider vmware_desktop 2>/dev/null || true
vagrant box add --name "$BOX_NAME" "$BOX_FILE"

info ""
info "Done. Use with:"
info "  PTAI_BOX=kali-arm64 VAGRANT_PROVIDER=vmware_desktop ./pt-ai up"

rm -rf "$WORK_DIR"
