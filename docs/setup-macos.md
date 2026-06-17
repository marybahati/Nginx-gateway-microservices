# Setup — macOS (Lima + Ubuntu 24.04 LTS)

Goal: by the end of this guide you have an Ubuntu 24.04 LTS VM on your Mac named `nginx-microservices`, with this repository mounted inside it and all three microservices running under systemd. ~15 minutes from a clean machine.

> This project assumes **Ubuntu Server 24.04 LTS (Noble Numbat)**. Other distros will mostly work but are not the supported target.

## 1. Host requirements

| Resource | Recommended host profile |
|---|---|
| CPU | 2 cores free for the VM |
| RAM | 4 GB free for the VM |
| Disk | 20 GB free |
| macOS | 13 Ventura or newer |

You do not need Docker, Vagrant, or VirtualBox. Lima ships its own VM driver.

## 2. Install Lima

```bash
brew install lima
limactl --version    # confirm it installed
```

If you don't have Homebrew yet: https://brew.sh

## 3. Create the dedicated host folder

The VM mounts **only** `~/nginx-microservices/` from your Mac — not your entire home directory. This way, a root command inside the VM cannot reach anything outside that folder.

> **This step is required before `limactl start`.** If the folder doesn't exist when Lima boots, you'll see `field mounts[0].location refers to a non-existent directory: "~/nginx-microservices"`. Lima will continue but the mount won't work. Create the folder first.

```bash
mkdir -p ~/nginx-microservices
ls -ld ~/nginx-microservices    # verify it's there before moving on
```

Clone or copy this repo into that folder:

```bash
cd ~/nginx-microservices
# git clone <your-repo-url> Nginx-gateway-microservices
```

Anything outside `~/nginx-microservices/` is invisible to the VM. Treat that folder as the bridge between host and VM.

## 4. Start the VM

Use the pinned config in this repo — it matches the cohort profile and forwards ports 80, 3001–3003.

```bash
cd ~/nginx-microservices/Nginx-gateway-microservices
limactl start --name=nginx-microservices ./service.yaml
```

> When Lima prompts `Proceed with the current configuration`, hit Enter. You may see a one-time `Non-strict YAML detected` warning on older Lima versions — it's safe to ignore as long as the warning doesn't reference an `unknown field`.

### VM profile (what `service.yaml` requests)

| Resource | VM profile |
|---|---|
| CPU | 1 |
| RAM | 1 GB |
| Disk | 8 GB |
| Hostname | `nginx-microservices` |
| Port forwards | 80, 3001, 3002, 3003 |

## 5. Get into the VM

```bash
limactl shell nginx-microservices
```

You should be at a shell like `bahati@nginx-microservices:~/nginx-microservices/Nginx-gateway-microservices$`. From here on every command runs **inside** the VM unless explicitly marked "on the host".

## 6. Find the repo inside the VM

Because you cloned into `~/nginx-microservices/` on the host and Lima mounts that folder, the repo is already visible:

```bash
cd ~/nginx-microservices/Nginx-gateway-microservices
ls
```

## 7. Verify you're on Ubuntu 24.04

```bash
uname -a
lsb_release -a
free -h
df -h
hostname    # → nginx-microservices
```

Expected: `Ubuntu 24.04 LTS` on the `Description:` line of `lsb_release -a`.

## 8. Run the installer

```bash
chmod +x install.sh uninstall.sh healthcheck.sh
sudo ./install.sh
./healthcheck.sh
make test
```

Expected:

```bash
curl http://localhost/service-a/health
curl http://service-b.internal:3002/health
curl http://service-c.internal:3003/health
curl http://localhost/service-a/greet-service-b
```

From the macOS host (ports forwarded by `service.yaml`):

```bash
curl http://localhost/service-a/health
```

## 9. Lima cheat sheet

```bash
limactl list
limactl shell nginx-microservices
limactl stop nginx-microservices
limactl start nginx-microservices
limactl delete nginx-microservices
```

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `limactl start` hangs at "writing image" | First-run cloud image download | Wait — first boot can take 3–5 min |
| `field mounts[0].location refers to a non-existent directory: "~/nginx-microservices"` | VM started before `mkdir -p ~/nginx-microservices` | Create the folder, then `limactl stop nginx-microservices && limactl start nginx-microservices` |
| `curl localhost/service-a/health` fails on the Mac host | Port forward not active yet | Try from inside `limactl shell` first; confirm `portForwards` in `service.yaml` |
| `Could not resolve host: service-b.internal` | `/etc/hosts` entry missing | `sudo ./install.sh` |
| "Permission denied" on `install.sh` | Forgot `chmod +x` | `chmod +x install.sh scripts/*.sh && sudo ./install.sh` |
| `lsb_release` shows 22.04 | Old Lima template | `limactl delete nginx-microservices` and recreate with `service.yaml` |
| Nginx 502 | Service A not running | `systemctl status service-a`; `journalctl -u service-a -n 30` |
