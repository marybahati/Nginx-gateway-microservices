# Setup — Windows (Multipass + Ubuntu 24.04 LTS)

Goal: by the end of this guide you have an Ubuntu 24.04 LTS VM on your Windows machine and this repository cloned inside it. ~15 minutes from a clean machine.

> This project assumes **Ubuntu Server 24.04 LTS (Noble Numbat)**. Other distros mostly work but are not the supported target.

## 1. Host requirements

| Resource | Recommended host profile |
|---|---|
| CPU | 2 cores free for the VM (CPU virtualization enabled in BIOS/UEFI) |
| RAM | 4 GB free for the VM |
| Disk | 20 GB free |
| Windows | 10 (build 19041+) or 11 — Home or Pro |

Confirm virtualization is on: open Task Manager → Performance → CPU → "Virtualization: Enabled". If it says Disabled, reboot into BIOS/UEFI and enable VT-x (Intel) or AMD-V (AMD).

## 2. Install Multipass (recommended path)

Multipass is Canonical's official tool for running Ubuntu VMs. One binary, works on Home and Pro.

> **Privilege scope.** The Administrator PowerShell below is a **one-time install step**. It registers Multipass as a Windows service. After install, every `multipass launch / shell / stop / delete` runs from a regular non-elevated PowerShell as your normal user. You should never need elevation again for the rest of this setup on the host side.

```powershell
# One-time. Run from an Administrator PowerShell:
winget install Canonical.Multipass
```

Close that elevated window. Open a **normal** (non-admin) PowerShell — that's where you'll spend the rest of the setup on the host:

```powershell
multipass version
```

Multipass picks Hyper-V on Windows Pro, or falls back to VirtualBox/QEMU on Home. You don't have to choose — let it.

## 3. Create the dedicated host folder

The VM mounts **only** `%USERPROFILE%\nginx-microservices` from your machine — not your entire user profile. This way, a root command inside the VM can never reach anything outside that folder.

```powershell
New-Item -ItemType Directory -Force -Path $HOME\nginx-microservices
```

Clone this repo into that folder, then continue inside the VM.

Anything outside `%USERPROFILE%\nginx-microservices` is invisible to the VM. Treat that folder as the bridge between host and VM.

## 4. Start the VM

```powershell
multipass launch 24.04 `
  --name nginx-microservices `
  --cpus 1 `
  --memory 1G `
  --disk 8G `
  --mount "${HOME}\nginx-microservices:/home/ubuntu/nginx-microservices"
```

The first launch downloads the Ubuntu 24.04 cloud image (a few minutes on a fresh machine). The `--mount` flag scopes the host share to exactly one folder. If you need to add or remove mounts after launch, use `multipass mount` / `multipass unmount`.

### VM profile

| Resource | VM profile |
|---|---|
| CPU | 1 |
| RAM | 1 GB |
| Disk | 8 GB |
| Host mount | `%USERPROFILE%\nginx-microservices` → `/home/ubuntu/nginx-microservices` (only) |

## 5. Get into the VM

```powershell
multipass shell nginx-microservices
```

Your prompt should look like `ubuntu@nginx-microservices:~$`. From here on, every command runs **inside** the VM unless explicitly marked "on the host".

## 6. Enter the repository

**Option A (recommended)** — clone into the shared folder so you can edit on Windows with VS Code and run inside the VM:

```bash
cd ~/nginx-microservices
git clone <your-repo-url> Nginx-gateway-microservices
cd Nginx-gateway-microservices
```

**Option B** — clone into a VM-only location (host stays clean):

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

To hit the API from Windows itself (outside the VM), grab the VM's IP:

```powershell
multipass info nginx-microservices    # look at the "IPv4" line
curl http://<that-ip>/service-a/health
```

## 9. Multipass cheat sheet

```powershell
multipass list                                                                           # what VMs do I have
multipass shell nginx-microservices                                                      # open a shell
multipass stop nginx-microservices                                                       # power off, keep state
multipass start nginx-microservices                                                      # power on
multipass delete nginx-microservices                                                     # mark for deletion
multipass purge                                                                          # actually free the disk after delete
multipass info nginx-microservices                                                       # IP, status, mounts, disk usage
multipass mount $HOME\nginx-microservices nginx-microservices:/home/ubuntu/nginx-microservices   # re-mount if needed
multipass unmount nginx-microservices:/home/ubuntu/nginx-microservices                   # remove the share
```

> Avoid mounting `%USERPROFILE%` (`$HOME`) wholesale — anything you mount is reachable by root inside the VM.

## Alternatives (use only if Multipass won't run)

| Option | When to pick it | Trade-off |
|---|---|---|
| **WSL2 (Ubuntu 24.04)** | Corporate laptop where you can't install a hypervisor, but WSL2 is allowed | Not a "real" VM — shares kernel with Windows. `systemd` works only with `[boot] systemd=true` in `/etc/wsl.conf` (Windows 11 / WSL ≥0.67). Fine for most of the workflow; some systemd behaviour may differ. |
| **Hyper-V + Ubuntu Server ISO** | Windows Pro, you want the full "install Linux from scratch" experience | More clicks, slower to set up. |
| **VirtualBox + Ubuntu Server ISO** | Windows Home where Hyper-V isn't available and Multipass refuses to start | Heaviest option. Battle-tested and well-documented. |
| **VMware Workstation Player** | You already have a VMware license | Free for personal use only; corporate use needs a paid license. |

### WSL2 quickstart (fallback)

```powershell
wsl --install -d Ubuntu-24.04
wsl -d Ubuntu-24.04
```

Inside the WSL distro, edit `/etc/wsl.conf` (create it if missing):

```ini
[boot]
systemd=true
```

Then `exit`, run `wsl --shutdown` from PowerShell, reopen the distro. Verify systemd is PID 1:

```bash
ps -p 1 -o comm=        # should print: systemd
```

After that, `sudo ./install.sh` and the rest of the workflow are the same. Caveats:

- `curl http://localhost/service-a/health` from Windows works because WSL2 forwards loopback.
- `systemctl reboot` will not reboot the host — use `wsl --shutdown` from Windows instead.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `multipass launch` hangs at "Retrieving image" | First-run image download | Wait — first boot can take 3–5 min on slow links |
| `launch failed: CPU does not support KVM extensions` | Virtualization disabled in BIOS | Reboot into BIOS/UEFI, enable VT-x or AMD-V |
| `Hyper-V is not available` on Home edition | Multipass needs a hypervisor backend | Install VirtualBox first, then `multipass set local.driver=virtualbox` |
| `Could not resolve host: service-b.internal` | `/etc/hosts` entry missing | `sudo ./install.sh` |
| `lsb_release` shows 22.04 | Used an old image name | `multipass delete nginx-microservices && multipass purge && multipass launch 24.04 --name nginx-microservices` |
| "Permission denied" on `install.sh` | Forgot `chmod +x` | `chmod +x install.sh uninstall.sh healthcheck.sh && sudo ./install.sh` |
| Nginx 502 on `/service-a/health` | Service A down | `systemctl status service-a`; `journalctl -u service-a -n 30` |
| WSL2: `systemctl` says "System has not been booted with systemd" | `systemd=true` not set or WSL not restarted | Edit `/etc/wsl.conf`, run `wsl --shutdown` from PowerShell, reopen |
