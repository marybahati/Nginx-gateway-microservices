# Setup — Linux (Multipass + Ubuntu 24.04 LTS)

Goal: by the end of this guide you have an Ubuntu 24.04 LTS VM on your Linux machine and this repository cloned inside it. ~10 minutes from a clean machine.

> This project assumes **Ubuntu Server 24.04 LTS (Noble Numbat)**. Other distros mostly work but are not the supported target.

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

## 2. Install Multipass (recommended path)

Multipass is Canonical's official tool for running Ubuntu VMs. One command, works on every distro.

```bash
sudo snap install multipass             # one-time
multipass version
```

If `multipass list` returns `permission denied`, add your user to the `multipass` group:

```bash
sudo usermod -aG multipass $USER
newgrp multipass
```

## 3. Create the dedicated host folder

The VM mounts **only** `~/nginx-microservices/` from your host — not your entire home directory.

```bash
mkdir -p ~/nginx-microservices
```

Clone this repo into that folder:

```bash
cd ~/nginx-microservices
# git clone <your-repo-url> Nginx-gateway-microservices
```

## 4. Start the VM

```bash
multipass launch 24.04 \
  --name nginx-microservices \
  --cpus 1 \
  --memory 1G \
  --disk 8G \
  --mount "$HOME/nginx-microservices:/home/ubuntu/nginx-microservices"
```

First launch downloads the Ubuntu 24.04 cloud image (a few minutes on a fresh machine).

### VM profile

| Resource | VM profile |
|---|---|
| CPU | 1 |
| RAM | 1 GB |
| Disk | 8 GB |
| Host mount | `~/nginx-microservices` → `/home/ubuntu/nginx-microservices` |

## 5. Get into the VM

```bash
multipass shell nginx-microservices
```

Your prompt should look like `ubuntu@nginx-microservices:~$`. From here on, every command runs **inside** the VM unless explicitly marked "on the host".

## 6. Clone or enter the repository

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

To hit the API from your host (outside the VM):

```bash
multipass info nginx-microservices   # look at the IPv4 line
curl http://<that-ip>/service-a/health
```

## 9. Multipass cheat sheet

```bash
multipass list
multipass shell nginx-microservices
multipass stop nginx-microservices
multipass start nginx-microservices
multipass delete nginx-microservices
multipass purge
multipass info nginx-microservices
```

## Alternatives

| Option | When to pick it | Trade-off |
|---|---|---|
| **Lima** | You prefer the same tool as macOS | `limactl start --name=nginx-microservices ./service.yaml` from the repo |
| **virt-manager (KVM)** | You already use libvirt | Heavier setup, full GUI control |
| **LXD / Incus** | You want fast boot | System containers share the host kernel |

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `multipass launch` hangs at "Retrieving image" | First-run image download | Wait 3–5 min |
| `launch failed: KVM not available` | KVM not loaded or disabled in BIOS | `sudo modprobe kvm-intel` (or `kvm-amd`); enable VT-x in BIOS |
| `Could not resolve host: service-b.internal` | `/etc/hosts` entry missing | `sudo ./install.sh` |
| `lsb_release` shows 22.04 | Wrong image | Delete VM and relaunch with `24.04` |
| "Permission denied" on `install.sh` | Forgot `chmod +x` | `chmod +x install.sh scripts/*.sh && sudo ./install.sh` |
| Nginx 502 on `/service-a/health` | Service A down | `systemctl status service-a` |
