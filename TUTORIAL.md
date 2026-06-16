# 🏛️ ATLAS PLATFORM — Complete Tutorial

> **Goal**: Turn a brand-new Ubuntu 24.04 VPS into a fully hardened, automated farming & automation server with Hermes Agent — in about 10 minutes.

---

## 📋 Before You Begin

### What You'll Need

| Item | Details |
|------|---------|
| **A VPS** | Ubuntu 24.04 LTS, 2GB RAM minimum, 20GB disk |
| **Root access** | Either direct root login or a user with `sudo` |
| **An SSH client** | Built-in on macOS/Linux; PuTTY or WSL on Windows |
| **Internet** | Your VPS must have public internet access |
| **~15 minutes** | Mostly automated, but you'll need to save your SSH key |

### Recommended VPS Providers
- DigitalOcean, Vultr, Linode, Hetzner Cloud, UpCloud
- Any provider that offers Ubuntu 24.04 with root access
- **1 vCPU, 2GB RAM** minimum; **2 vCPU, 4GB RAM** recommended for heavier automation

---

## Step 1: Get a VPS

1. **Sign up** with your preferred VPS provider
2. **Create a new droplet/instance**:
   - **OS**: Ubuntu 24.04 LTS (Noble Numbat)
   - **Size**: 2GB RAM minimum (4GB recommended)
   - **Region**: Choose one close to your target services
   - **Authentication**: SSH key (recommended) or root password
3. **Note your server's IP address** — you'll need it in the next step

> 💡 **Tip**: Add a firewall at the provider level allowing SSH (port 22) only. ATLAS PLATFORM will handle everything else.

---

## Step 2: Connect via SSH

From your local terminal:

```bash
# If you set up an SSH key with your provider:
ssh root@<your-server-ip>

# If you used a root password (you'll be prompted):
ssh root@<your-server-ip>
```

Once connected, you should see something like:
```
Welcome to Ubuntu 24.04 LTS (GNU/Linux 6.8.0-x-generic x86_64)
```

### Verify you're ready:

```bash
# Check Ubuntu version
lsb_release -a
# Should show: Ubuntu 24.04 LTS

# Check you're root
whoami
# Should show: root

# Check internet
ping -c 2 1.1.1.1
# Should show: 2 packets transmitted, 2 received
```

---

## Step 3: Run the ATLAS PLATFORM Installer

### Option A: One-liner (recommended)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/leonidastcejorp/atlas-platform/main/install.sh)
```

### Option B: Manual clone

```bash
apt update && apt install -y git
git clone https://github.com/leonidastcejorp/atlas-platform.git /opt/atlas-platform
cd /opt/atlas-platform
bash setup.sh
```

### What You'll See

The script runs through 10 phases, each clearly labeled:

```
╔══════════════════════════════════════════════════════════════╗
║              🏛️  ATLAS PLATFORM                               ║
║              Infrastructure Provisioning System              ║
╚══════════════════════════════════════════════════════════════╝

[PHASE 0/9] ⚙️  System Base
  ✓ Ubuntu 24.04 detected
  ✓ Internet connectivity confirmed
  ✓ Running as root
  ✓ Packages updated
  ...

[PHASE 1/9] 🛡️  Kernel Hardening
  ✓ Sysctl security configs applied
  ✓ BBR congestion control enabled
  ✓ Kernel modules blacklisted
  ...

[PHASE 2/9] 🔑 SSH Hardening
  ⚠️  GENERATING SSH KEY — SAVE THIS NOW!
  
  -----BEGIN OPENSSH PRIVATE KEY-----
  b3Blb... (your key here) ...blDQ=
  -----END OPENSSH PRIVATE KEY-----
  
  ⏳ Copy your key! Waiting 15 seconds...
  
  ✓ SSH key generated
  ✓ SSH config hardened
  ...
```

> ⚠️ **CRITICAL MOMENT**: During Phase 2, the script generates your SSH key and displays it with a **15-second pause**. **Copy the entire key** (including `-----BEGIN` and `-----END` lines) and save it to your local machine as `atlas_ed25519`. If you miss it, the key is at `/root/.ssh/atlas_ed25519` — but you must copy it BEFORE the script finishes, as password login is disabled after deployment!

---

## Step 4: Save Your SSH Key

### While the script is paused (window of 15 seconds):

1. **Select** the entire private key block (from `-----BEGIN` to `-----END`)
2. **Copy** it (Ctrl+C / Cmd+C)
3. On your **local machine**, create a file:
   ```bash
   # On your LOCAL machine, not the server:
   nano ~/.ssh/atlas_ed25519
   ```
4. **Paste** the key and save
5. **Set correct permissions**:
   ```bash
   chmod 600 ~/.ssh/atlas_ed25519
   ```

### If you miss the window:
The key is saved at `/root/.ssh/atlas_ed25519` on the server. After the script finishes but **before you disconnect** from your original SSH session:

```bash
cat /root/.ssh/atlas_ed25519
# Copy the output immediately
```

Then open a **second terminal** and test the new connection before closing the first:

```bash
# On your LOCAL machine:
ssh -i ~/.ssh/atlas_ed25519 -p 2222 root@<your-server-ip>
```

---

## Step 5: Reconnect via the New SSH Port

After the script completes, your SSH has moved to port **2222**. Your original connection on port 22 will still work, but new connections must use port 2222.

```bash
# Disconnect from the old session (or keep it as backup)
exit

# Reconnect using your new key on port 2222
ssh -i ~/.ssh/atlas_ed25519 -p 2222 root@<your-server-ip>
```

> 💡 **Pro tip**: Add an SSH config entry to simplify:
> ```bash
> # Add to ~/.ssh/config on your LOCAL machine:
> Host atlas
>     HostName <your-server-ip>
>     Port 2222
>     User root
>     IdentityFile ~/.ssh/atlas_ed25519
> ```
> Then just run: `ssh atlas`

---

## Step 6: Configure Hermes Agent

Now that the server is hardened and tools are installed, set up Hermes Agent.

### 6a. Switch to the hermes user

```bash
su - hermes
```

### 6b. Run setup

```bash
hermes setup
```

Follow the interactive prompts to configure:
- API provider (OpenAI, Anthropic, etc.)
- Tool configurations
- Default preferences

### 6c. Set up tools

```bash
hermes setup tools
```

This configures:
- Firecrawl (web scraping)
- Browser automation
- Image generation
- Speech/text-to-speech

### 6d. Verify the service

```bash
# Back as root:
systemctl status hermes-agent
# Should show: active (running)

# Check logs:
journalctl -u hermes-agent -f
```

---

## Step 7: Configure API Keys & Environment

Edit the hermes user's environment:

```bash
# As root or hermes:
sudo -u hermes mkdir -p /home/hermes/.config/hermes
sudo -u hermes nano /home/hermes/.config/hermes/.env
```

Add your API keys:

```bash
# Example .env file (fill in your actual keys)
OPENAI_API_KEY="sk-..."
ANTHROPIC_API_KEY="sk-ant-..."
FIRECRAWL_API_KEY="fc-..."
# Add any other provider keys you use
```

Restart the agent:

```bash
systemctl restart hermes-agent
```

---

## Step 8: Deploy Your First Cron Job (Optional)

ATLAS PLATFORM is built for automation. Here's how to schedule Hermes tasks:

```bash
# Edit hermes user's crontab
crontab -e -u hermes

# Example: Run a daily monitoring task at 6 AM WIB
0 6 * * * /opt/atlas/venv/bin/hermes run --task "Check server health and report" >> /var/log/atlas-cron.log 2>&1

# Example: Run a farming task every 4 hours
0 */4 * * * /opt/atlas/venv/bin/hermes run --task "Execute farming cycle" >> /var/log/atlas-farm.log 2>&1
```

---

## Step 9: Verify Everything

Run through this checklist to confirm everything is working:

### Security Checklist

```bash
# 1. SSH hardening
sshd -T | grep -E "(port|passwordauth|pubkeyauth|permitroot)"
# Should show: port 2222, passwordauth no, pubkeyauth yes, permitroot prohibit-password

# 2. Firewall
ufw status verbose
# Should show: Status: active, Default: deny (incoming), allow 2222

# 3. fail2ban
fail2ban-client status sshd
# Should show active jails

# 4. auditd
auditctl -l
# Should list all monitoring rules

# 5. Geo-blocking
ipset list ATLAS_BLACKLIST | wc -l
# Should show thousands of entries
ipset list ATLAS_WHITELIST
# Should show ID (Indonesia) entries

# 6. ZRAM swap
swapon --show
# Should show /dev/zram0

# 7. Unattended upgrades
systemctl status unattended-upgrades
# Should be active
```

### Tools Checklist

```bash
# Check Go
go version
# Should show: go1.22.5 linux/amd64

# Check Node
node --version
# Should show: v22.x.x

# Check PM2
pm2 --version
# Should show version

# Check Playwright
python3 -c "from playwright.sync_api import sync_playwright; print('OK')"

# Check Go security tools
nuclei --version
subfinder --version
httpx --version
```

### Hermes Agent Checklist

```bash
# Service status
systemctl status hermes-agent

# Check it's running as 'hermes' user
ps aux | grep hermes-agent | grep -v grep
# Should show process running as 'hermes' user

# Read systemd sandboxing
systemctl show hermes-agent | grep -E "(NoNewPrivileges|ProtectSystem|ProtectHome|PrivateTmp)"
# Should show various sandboxing protections
```

---

## Step 10: Run Security Audits

ATLAS PLATFORM installs multiple detection tools. Run them to verify your hardening:

```bash
# AIDE — Initialize database and check
aideinit
aide --check

# RKHunter — Scan for rootkits
rkhunter --check --skip-keypress

# Lynis — Full security audit
lynis audit system
```

---

## 🔧 Troubleshooting Common Issues

### "This script requires Ubuntu 24.04"
ATLAS PLATFORM is specifically designed for Ubuntu 24.04. If you're running a different version:
- **Upgrade**: `do-release-upgrade`
- **Or use a fresh 24.04 VPS**

### "This script must be run as root"
Use `sudo` or log in directly as root:
```bash
sudo bash setup.sh
```

### SSH key lost / locked out
If you lose your SSH key and get locked out:
1. Use your VPS provider's **web console** / out-of-band access
2. Log in via the console
3. Reset SSH: `cat /root/.ssh/atlas_ed25519.pub > /root/.ssh/authorized_keys`
4. Or temporarily re-enable password auth by editing `/etc/ssh/sshd_config.d/99-atlas-hardening.conf`

### Hermes Agent won't start
```bash
# Check the logs
journalctl -u hermes-agent -n 50 --no-pager

# Common fixes:
# 1. Reinstall hermes-agent
sudo -u hermes /opt/atlas/venv/bin/pip install --upgrade hermes-agent

# 2. Check config
cat /home/hermes/.config/hermes/config.yaml

# 3. Manually test
sudo -u hermes /opt/atlas/venv/bin/hermes --help
```

### Geo-blocking blocking legitimate traffic
If you need to allow a specific country, add it to the whitelist:
```bash
# Add a country (e.g., Singapore)
curl -s https://www.ipdeny.com/ipblocks/data/countries/sg.zone | \
  xargs -I{} ipset add ATLAS_WHITELIST {} 2>/dev/null
ufw reload
```

### Low memory / swap issues
```bash
# Check ZRAM status
zramctl
# Shows: /dev/zram0 with 1G size

# Increase if needed (edit the service file):
systemctl edit atlas-zram
# Change echo 1G to echo 2G in ExecStart
systemctl restart atlas-zram
```

---

## 📊 What's Running After Deployment

| Service | Port | User | Purpose |
|---------|------|------|---------|
| SSH | 2222 | root (key only) | Remote administration |
| UFW | - | root | Firewall with geo-blocking |
| fail2ban | - | root | Intrusion prevention |
| auditd | - | root | File integrity monitoring |
| hermes-agent | - | hermes | AI automation agent |
| ZRAM | - | root | Compressed swap (1GB) |
| cron | - | hermes | Scheduled automation tasks |

---

## 🎉 You're Done!

Your ATLAS PLATFORM server is now:
- ✅ **Hardened** — SSH key-only, firewall, geo-blocking, kernel hardening
- ✅ **Monitored** — auditd, AIDE, RKHunter, Lynis, fail2ban
- ✅ **Automated** — Hermes Agent ready for farming and automation tasks
- ✅ **Self-maintaining** — Unattended security updates, log rotation
- ✅ **Fast** — BBR congestion control, ZRAM compressed swap

### Next Steps

1. **Read the deployment log**: `less /var/log/atlas-deploy.log`
2. **Explore Hermes Agent**: `su - hermes && hermes --help`
3. **Set up your first automation**: Schedule a cron job or deploy a PM2 process
4. **Join the community**: Share your setup, contribute improvements

---

**🏛️ ATLAS PLATFORM** — *Provisions. Hardens. Automates.*
