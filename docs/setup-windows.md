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

Confirm virtualization is on: Task Manager → Performance → CPU → "Virtualization: Enabled".

## 2. Install Multipass (recommended path)

```powershell
# One-time, from an Administrator PowerShell:
winget install Canonical.Multipass
```

Open a **normal** (non-admin) PowerShell for everything else:

```powershell
multipass version
```

## 3. Create the dedicated host folder

The VM mounts **only** `%USERPROFILE%\nginx-microservices` from your machine — not your entire user profile.

```powershell
New-Item -ItemType Directory -Force -Path $HOME\nginx-microservices
```

Clone this repo into that folder, then continue inside the VM.

## 4. Start the VM

```powershell
multipass launch 24.04 `
  --name nginx-microservices `
  --cpus 1 `
  --memory 1G `
  --disk 8G `
  --mount "${HOME}\nginx-microservices:/home/ubuntu/nginx-microservices"
```

### VM profile

| Resource | VM profile |
|---|---|
| CPU | 1 |
| RAM | 1 GB |
| Disk | 8 GB |
| Host mount | `%USERPROFILE%\nginx-microservices` → `/home/ubuntu/nginx-microservices` |

## 5. Get into the VM

```powershell
multipass shell nginx-microservices
```

Your prompt should look like `ubuntu@nginx-microservices:~$`. From here on, every command runs **inside** the VM unless explicitly marked "on the host".

## 6. Enter the repository

**Option A (recommended)** — shared mount:

```bash
cd ~/nginx-microservices/Nginx-gateway-microservices
ls
```

**Option B** — VM-only clone:

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

From Windows (grab the VM IP):

```powershell
multipass info nginx-microservices
curl http://<IPv4>/service-a/health
```

## 9. Multipass cheat sheet

```powershell
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
| **WSL2 (Ubuntu 24.04)** | Hypervisor install blocked | Not a full VM; enable `systemd=true` in `/etc/wsl.conf` |
| **Hyper-V + Ubuntu ISO** | Windows Pro, want bare-metal install | More setup steps |
| **VirtualBox + Ubuntu ISO** | Multipass won't start on Home edition | Slower but reliable |

### WSL2 quickstart (fallback)

```powershell
wsl --install -d Ubuntu-24.04
```

Inside WSL, create `/etc/wsl.conf`:

```ini
[boot]
systemd=true
```

Then `wsl --shutdown` from PowerShell and reopen the distro. Verify:

```bash
ps -p 1 -o comm=    # should print: systemd
```

After that, `sudo ./install.sh` and the rest of the workflow are the same.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `multipass launch` hangs at "Retrieving image" | First-run download | Wait 3–5 min |
| `Hyper-V is not available` on Home | No hypervisor backend | Install VirtualBox, then `multipass set local.driver=virtualbox` |
| `Could not resolve host: service-b.internal` | `/etc/hosts` entry missing | `sudo ./install.sh` |
| WSL2: `systemctl` says systemd not booted | `systemd=true` missing | Edit `/etc/wsl.conf`, `wsl --shutdown`, reopen |
| "Permission denied" on `install.sh` | Forgot `chmod +x` | `chmod +x install.sh scripts/*.sh && sudo ./install.sh` |
