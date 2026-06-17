# 🏛️ ATLAS PLATFORM

**Infrastructure Provisioning System — One command to harden, automate, and deploy.**

ATLAS PLATFORM is a comprehensive infrastructure provisioning system that transforms a fresh Ubuntu 24.04 VPS into a fully hardened, fully automated farming and automation server with [Hermes Agent](https://github.com/NousResearch/hermes-agent). 

One line. Ten phases. Battle-ready.

---

## 🎯 What It Does

Run a single command, and ATLAS PLATFORM will:

1. **Harden SSH** — Non-standard port, key-only auth, cipher restrictions
2. **Configure firewall** — UFW with geo-blocking (RU/CN/UZ/LT blocked, ID whitelisted)
3. **Deploy detection** — auditd, AIDE, RKHunter, Lynis, fail2ban with recidive
4. **Tune kernel** — BBR congestion control, sysctl hardening, module blacklisting
5. **Set up ZRAM** — 1GB zstd compressed swap
6. **Install tools** — Go 1.22.5, Node 22, PM2, Yarn, Python venv, Playwright, web3.py
7. **Deploy Hermes Agent** — Sandboxed systemd service with dedicated user
8. **Configure maintenance** — Unattended security upgrades, journald limits, MOTD

---

## 📋 Prerequisites

| Requirement | Details |
|-------------|---------|
| **OS** | Ubuntu 24.04 LTS (Noble Numbat) — fresh install recommended |
| **User** | `root` access (or sudo-capable user) |
| **Network** | Public internet access via IPv4 |
| **Ports** | 2222 (SSH), 80/443 (optional, if you open them post-install) |
| **Disk** | 8GB minimum, 20GB+ recommended |

---

## 🚀 Quick Start

### One-liner (recommended)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/leonidastcejorp/atlas-platform/main/install.sh)
```

### Manual download

```bash
git clone https://github.com/leonidastcejorp/atlas-platform.git /opt/atlas-platform
cd /opt/atlas-platform
bash setup.sh
```

> ⚠️ **IMPORTANT**: The SSH key will be generated and displayed during Phase 2. **Save it immediately** — you have 15 seconds to copy the private key. After the script finishes, your SSH port moves to 2222 with key-only authentication.

---

## 📦 What It Installs

| Component | Version / Details |
|-----------|-------------------|
| **Go** | 1.22.5 (linux/amd64) |
| **Node.js** | 22.x LTS (via NodeSource) |
| **PM2** | Latest (global, via npm) |
| **Yarn** | Latest (via npm) |
| **Python** | 3.12 venv (isolated at `/opt/atlas/venv`) |
| **Playwright** | Latest (Chromium + dependencies) |
| **web3.py** | Latest (in venv) |
| **Go Security Tools** | nuclei, subfinder, httpx |
| **Hermes Agent** | Latest (via pip in venv) |
| **System Packages** | ufw, fail2ban, auditd, aide, rkhunter, lynis, ipset, curl, git, build-essential, etc. |

---

## 🛡️ Security Hardening

| Layer | Implementation |
|-------|---------------|
| **SSH** | Port 2222, key-only auth, no root password login, rate limited, strong ciphers only |
| **Firewall** | UFW: allow 2222, deny all incoming by default, geo-blocking via ipset |
| **Geo-blocking** | Ban RU, CN, UZ, LT subnets; whitelist ID (Indonesia) |
| **Intrusion Detection** | fail2ban (sshd + recidive perma-ban), auditd file monitoring, AIDE integrity checks |
| **Malware Scanning** | RKHunter, Lynis audit |
| **Kernel Hardening** | ASLR, restricted ptrace/BPF/userns, SYN cookies, source-route blocking |
| **Unattended Upgrades** | Security patches auto-applied daily, no auto-reboot |
| **Logging** | auditd immutable rules, journald capped at 200MB compressed |

---

## 📁 File Structure

```
atlas-platform/
├── setup.sh                          # Main deployment script (10 phases)
├── install.sh                        # Bootstrap one-liner launcher
├── README.md                         # This file
├── TUTORIAL.md                       # Step-by-step walkthrough
├── configs/
│   ├── ssh/hardening.conf            # SSH drop-in hardening config
│   ├── sysctl/
│   │   ├── 99-atlas-perf.conf        # BBR + network performance
│   │   ├── 99-atlas-hardening.conf   # Kernel security hardening
│   │   └── 99-atlas-optimizations.conf # Memory/filesystem optimizations
│   ├── ufw/                          # (UFW rules applied inline)
│   ├── fail2ban/
│   │   ├── sshd.conf                 # SSH jail (3 tries/10min/1hr)
│   │   └── recidive.conf            # Repeat offender perma-ban
│   ├── auditd/atlas.rules           # File monitoring rules (immutable)
│   ├── zram/atlas-zram.service      # ZRAM zstd swap (1GB)
│   ├── journald/atlas.conf          # Journald 200MB limit
│   ├── motd/99-atlas                # On-login system summary
│   └── modprobe/blacklist-hardening.conf # Kernel module blacklist
└── docs/                             # Additional documentation
```

---

## 🔧 Post-Install Steps

After ATLAS PLATFORM finishes deploying:

### 1. Save your SSH key
The key prints to screen. Copy `~/.ssh/atlas_ed25519` (private) and keep it safe.

### 2. Reconnect via port 2222
```bash
ssh -i atlas_ed25519 -p 2222 root@<your-server-ip>
```

### 3. Deploy Docker infrastructure stack
```bash
cd /opt/atlas-platform/stacks/infra
cp .env.example .env
# Edit .env, set TRAEFIK_DASHBOARD_HOST & strong password
bash deploy.sh
```

### 4. Configure Hermes Agent
```bash
su - hermes
hermes setup            # Interactive configuration
hermes setup tools      # Set up required API tools
```

### 5. Add your tools and cron jobs
```bash
# Example: deploy a monitoring cron job
crontab -e -u hermes
```

### 6. Verify everything
```bash
# Check services
systemctl status hermes fail2ban auditd
# Check Docker stack
docker compose -f /opt/atlas-platform/stacks/infra/docker-compose.yml ps
# Run security audit
lynis audit system
# Check firewall
ufw status verbose
```

## 🧰 Companion Repositories

| Repo | Purpose | Link |
|------|---------|------|
| **Talos Engine** | Automation framework: airdrop farming, bug bounty recon, monitoring | [leonidastcejorp/talos-engine](https://github.com/leonidastcejorp/talos-engine) |

## 🔍 Troubleshooting

### SSH connection refused after deployment
- Make sure you're connecting on port **2222**, not 22
- Use your key: `ssh -i atlas_ed25519 -p 2222 root@<ip>`
- If locked out, use your VPS provider's console/out-of-band access

### Hermes Agent won't start
```bash
journalctl -u hermes -n 50 --no-pager
# Common fixes:
# - Ensure /opt/atlas/venv exists and has hermes-agent installed
# - Check hermes user can read /opt/atlas/
```

### Geo-blocking issues
```bash
# Check ipset lists
ipset list ATLAS_BLACKLIST | head -20
ipset list ATLAS_WHITELIST | head -20
# Reload if needed
ufw reload
```

### Deployment log
Full deployment log at: `/var/log/atlas-deploy.log`
```bash
tail -100 /var/log/atlas-deploy.log
```

---

## ⚙️ Deployment Phases

| Phase | Name | Actions |
|-------|------|---------|
| **0** | System Base | OS check, apt update, base packages, DNS, timezone, Python |
| **1** | Kernel Hardening | sysctl tuning, module blacklist |
| **2** | SSH Hardening | Key generation, drop-in config, cipher restrictions |
| **3** | Firewall + fail2ban | UFW rules, fail2ban sshd + recidive |
| **4** | Geo-Blocking | ipset country-level blacklist/whitelist |
| **5** | Detection Tools | auditd, AIDE, RKHunter, Lynis |
| **6** | Maintenance | Auto-upgrades, journald, ZRAM swap |
| **7** | Toolchain | Go, Node, PM2, Playwright, web3, Go security tools |
| **8** | Hermes Agent | Install, system user, systemd sandboxed service |
| **9** | Finalization | MOTD, bashrc, cleanup, summary |

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

---

## 📄 License

MIT License — see [LICENSE](LICENSE) file for details.

---

**🏛️ ATLAS PLATFORM** — *Provisions. Hardens. Automates.*
