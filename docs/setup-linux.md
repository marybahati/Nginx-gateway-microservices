# Setup — Linux (Multipass + Ubuntu 24.04 LTS)

Goal: by the end of this guide you have an Ubuntu 24.04 LTS VM on your Linux machine and this repository cloned inside it. ~10 minutes from a clean machine.

> This project assumes **Ubuntu Server 24.04 LTS (Noble Numbat)**. Other distros mostly work but are not the supported target.
>
> **"But I'm already on Linux — why do I need a VM?"** Because `install.sh` writes to `/etc/hosts`, installs systemd units, and touches Nginx config. You do *not* want to run that against your real workstation. The VM keeps blast radius zero.

## 1. Host requirements

| Resource | Recommended host profile |
|---|---|
| CPU | 2 cores free, with KVM extensions enabled (VT-x / AMD-V) |
| RAM | 4 GB free for the VM |
| Disk | 20 GB free |
| Distro | Any modern Linux — Ubuntu, Fedora, Arch, Debian, openSUSE, etc. |

Confirm KVM is available:

```bash
egrep -c '(vmx|svm)' /proc/cpuinfo    # >0 means CPU supports it
lsmod | grep kvm                       # kvm + kvm_intel/kvm_amd should be loaded
```

If both are good, you can use any of the options below. If KVM isn't loaded, you'll be limited to VirtualBox or QEMU-TCG (slow).

## 2. Install Multipass (recommended path)

Multipass is Canonical's official tool for running Ubuntu VMs. One command, works on every distro.

> **Privilege scope.** The `sudo` below is a **one-time install step**. After install, every `multipass launch / shell / stop / delete` runs as your normal user — no sudo. The snap-installed Multipass daemon runs as root in the background; your client commands talk to it via a socket.

```bash
sudo snap install multipass             # one-time. Ubuntu, Fedora (with snapd), most distros
# OR — on distros without snap, use the official installer from
# https://canonical.com/multipass/install
```

Verify (no sudo from here on):

```bash
multipass version
```

If `multipass list` returns `permission denied` on your distro, your user needs to be in the `multipass` group:

```bash
sudo usermod -aG multipass $USER
newgrp multipass                        # apply the group in this shell, no logout needed
```

Multipass uses QEMU+KVM on Linux by default.

## 3. Create the dedicated host folder

The VM mounts **only** `~/nginx-microservices/` from your host — not your entire home directory. This way, a root command inside the VM can never reach anything outside that folder.

```bash
mkdir -p ~/nginx-microservices
```

Clone this repo into that folder:

```bash
cd ~/nginx-microservices
git clone <your-repo-url> Nginx-gateway-microservices
```

Anything outside `~/nginx-microservices/` is invisible to the VM. Treat that folder as the bridge between host and VM.

## 4. Start the VM

```bash
multipass launch 24.04 \
  --name nginx-microservices \
  --cpus 1 \
  --memory 1G \
  --disk 8G \
  --mount "$HOME/nginx-microservices:/home/ubuntu/nginx-microservices"
```

First launch downloads the Ubuntu 24.04 cloud image (a few minutes on a fresh machine). The `--mount` flag scopes the host share to exactly one folder. Use `multipass mount` / `multipass unmount` afterwards to add or remove shares.

### VM profile

| Resource | VM profile |
|---|---|
| CPU | 1 |
| RAM | 1 GB |
| Disk | 8 GB |
| Host mount | `~/nginx-microservices` → `/home/ubuntu/nginx-microservices` (only) |

## 5. Get into the VM

```bash
multipass shell nginx-microservices
```

Your prompt should look like `ubuntu@nginx-microservices:~$`. From here on, every command runs **inside** the VM unless explicitly marked "on the host".

## 6. Enter the repository

**Option A (recommended)** — use the shared mount:

```bash
cd ~/nginx-microservices/Nginx-gateway-microservices
ls
```

**Option B** — clone into a VM-only location:

```bash
sudo apt-get update && sudo apt-get install -y git
git clone <your-repo-url> ~/Nginx-gateway-microservices
cd ~/Nginx-gateway-microservices
```

## 7. Verify you're on Ubuntu 24.04

```bash
uname -a
lsb_release -a
free -h
df -h
```

Expected: `Ubuntu 24.04 LTS` on the `Description:` line.

## 8. Run the installer

```bash
chmod +x install.sh uninstall.sh healthcheck.sh
sudo ./install.sh
./healthcheck.sh
make test
```

Validation:

```bash
curl http://localhost/service-a/health
curl http://service-b.internal:3002/health
curl http://service-c.internal:3003/health
curl http://localhost/service-a/greet-service-b
```

To hit the API from your host (outside the VM), grab the VM's IP:

```bash
multipass info nginx-microservices   # look at the "IPv4" line
curl http://<that-ip>/service-a/health
```

## 9. Multipass cheat sheet

```bash
multipass list                                                                         # what VMs do I have
multipass shell nginx-microservices                                                    # open a shell
multipass stop nginx-microservices                                                     # power off, keep state
multipass start nginx-microservices                                                    # power on
multipass delete nginx-microservices                                                   # mark for deletion
multipass purge                                                                        # actually free the disk after delete
multipass info nginx-microservices                                                     # IP, status, mounts, disk
multipass mount ~/nginx-microservices nginx-microservices:/home/ubuntu/nginx-microservices   # re-mount if needed
multipass unmount nginx-microservices:/home/ubuntu/nginx-microservices                 # remove the share
```

> Avoid mounting `$HOME` wholesale — anything you mount is reachable by root inside the VM.

## Alternatives (use only if Multipass won't run on your host)

| Option | When to pick it | Trade-off |
|---|---|---|
| **Lima** | You prefer the same tool as macOS | `limactl start --name=nginx-microservices ./service.yaml` from the repo |
| **virt-manager (KVM/libvirt)** | You already use libvirt | Heavier setup, but uses the kernel hypervisor directly. GUI for VM management. |
| **LXD / Incus** | You want fast boot (~1s) | System containers share the host kernel. Fine for this project. |
| **VirtualBox** | KVM unavailable | Slower than KVM. Conflicts with KVM if both are loaded — pick one. |

### virt-manager quickstart (fallback)

> **Privilege scope.** The `sudo` commands below are **one-time setup**. Adding yourself to `libvirt` and `kvm` means every later `virt-manager` / `virsh` invocation runs as your normal user with no sudo. Group membership only takes effect in *new* shells — either log out and back in, or use `newgrp` in your current shell.

```bash
# Ubuntu/Debian (one-time):
sudo apt install qemu-kvm libvirt-daemon-system virt-manager
sudo usermod -aG libvirt,kvm $USER

# Fedora (one-time):
sudo dnf install @virtualization
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt,kvm $USER

# Apply without logging out:
newgrp libvirt

# Verify:
virsh list --all
virt-manager
```

In the GUI: **File → New Virtual Machine → Local install media** → point at an Ubuntu 24.04 Server ISO → 1 CPU / 1 GB RAM / 8 GB disk → finish.

### LXD quickstart (fallback)

```bash
sudo snap install lxd
sudo lxd init                                # accept defaults
sudo usermod -aG lxd $USER && newgrp lxd
lxc launch ubuntu:24.04 nginx-microservices \
  -c limits.cpu=1 -c limits.memory=1GiB
lxc shell nginx-microservices
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `multipass launch` hangs at "Retrieving image" | First-run image download | Wait — first boot can take 3–5 min |
| `launch failed: KVM not available` | KVM not loaded or disabled in BIOS | `sudo modprobe kvm-intel` (or `kvm-amd`); enable VT-x in BIOS |
| `cannot connect to /var/snap/multipass/common/multipass_socket` | snap service not running | `sudo systemctl start snap.multipass.multipassd` |
| Conflict between KVM and VirtualBox | Both want exclusive CPU access | Pick one: `sudo modprobe -r kvm_intel` to use VirtualBox |
| `Could not resolve host: service-b.internal` | `/etc/hosts` entry missing | `sudo ./install.sh` |
| `lsb_release` shows 22.04 | Wrong image | `multipass delete nginx-microservices && multipass purge && multipass launch 24.04 ...` |
| "Permission denied" on `install.sh` | Forgot `chmod +x` | `chmod +x install.sh uninstall.sh healthcheck.sh && sudo ./install.sh` |
| Nginx 502 on `/service-a/health` | Service A down | `systemctl status service-a`; `journalctl -u service-a -n 30` |
