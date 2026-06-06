# ARM64 Box

The `kalilinux/rolling` box on Vagrant Cloud is x86_64 only. On Apple Silicon
with VMware Fusion you need to build a local box from the official Kali ARM64
installer ISO. `build.sh` automates everything except the ~20-minute GUI install.

> This script is macOS + VMware Fusion specific. Linux ARM64 hosts are not supported.

## Prerequisites

```sh
brew install vagrant
vagrant plugin install vagrant-vmware-desktop
```

VMware Fusion 13+ Pro (free for personal use) must be installed, plus the
[VMware Utility](https://developer.hashicorp.com/vagrant/install/vmware)
(a separate HashiCorp package required by the plugin).

## Build the box

```sh
./box/build.sh
```

The script will:
1. Download and verify the latest Kali ARM64 installer ISO from kali.org
2. Create a VMware Fusion VM (40 GB disk, 4 GB RAM, 4 vCPUs)
3. Boot the VM — **you install Kali via the GUI** (~20 min)
4. Configure the VM as a Vagrant base box via SSH
5. Package and register it locally as `kali-arm64`

### During the GUI install

Follow these settings so the automated post-install step works:

| Field | Value |
|---|---|
| Hostname | `kali-ptai` |
| Username | `vagrant` |
| Password | `vagrant` |
| Partitioning | Guided – use entire disk, all files in one partition |
| Software | keep defaults; ensure **SSH server** and **open-vm-tools** are included |
| GRUB | install to the primary EFI partition |

After the installer reboots into Kali, log in as `vagrant` and run the
SSH key setup command shown in the terminal — then press Enter in the script.

## Use the box

```sh
export PTAI_BOX=kali-arm64
export VAGRANT_PROVIDER=vmware_desktop
./kali up
```

Or add both to `config/.env` (copy from `config/engagement.env.example`).

## Notes

- The `.box` file and `.build/` directory are gitignored — rebuild when
  you need a newer Kali release.
- To rebuild: run `./box/build.sh` again; it removes the old registered box
  and replaces it.
