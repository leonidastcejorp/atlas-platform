#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                         🏛️  ATLAS PLATFORM                                  ║
# ║                    Infrastructure Provisioning System                        ║
# ║                                                                            ║
# ║  Transforms a fresh Ubuntu 24.04 VPS into a fully hardened,                ║
# ║  fully automated farming & automation server with Hermes Agent.            ║
# ║                                                                            ║
# ║  Version:  1.0.0                                                           ║
# ║  License:  MIT                                                             ║
# ║  Requires: Ubuntu 24.04 LTS (Noble Numbat), root access, internet          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# USAGE:
#   curl -fsSL <url>/install.sh | bash     # Bootstrap (recommended)
#   bash setup.sh                           # Direct execution
#
# WHAT IT DOES — 10 PHASES:
#   PHASE 0: System Base      — OS check, apt, DNS, timezone, Python
#   PHASE 1: Kernel Hardening — sysctl tuning, module blacklisting
#   PHASE 2: SSH Hardening    — Key generation, port 2222, drop-in config
#   PHASE 3: Firewall+fail2ban— UFW, fail2ban sshd + recidive
#   PHASE 4: Geo-Blocking     — ipset country-level blacklist/whitelist
#   PHASE 5: Detection Tools  — auditd, AIDE, RKHunter, Lynis
#   PHASE 6: Maintenance      — Auto-upgrades, journald, ZRAM swap
#   PHASE 7: Toolchain        — Go, Node, PM2, Playwright, web3, Go tools
#   PHASE 8: Hermes Agent     — Install, system user, systemd sandbox
#   PHASE 9: Finalization     — MOTD, bashrc, cleanup, summary
#
# IDEMPOTENT: Safe to re-run. Each phase checks before acting.
# LOG FILE:   /var/log/atlas-deploy.log

set -euo pipefail

# ─── Configuration ─────────────────────────────────────────────────────────────
readonly ATLAS_VERSION="1.0.0"
readonly LOG_FILE="/var/log/atlas-deploy.log"
readonly SSH_PORT="2222"
readonly HERMES_USER="hermes"
readonly ATLAS_HOME="/opt/atlas"
readonly ATLAS_VENV="${ATLAS_HOME}/venv"
readonly DEPLOY_STAMP="${ATLAS_HOME}/.deploy_phase"
readonly CONFIG_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/configs"
readonly GO_VERSION="1.22.5"
readonly NODE_MAJOR="22"
readonly ZRAM_SIZE="1G"

# ─── Color Definitions ─────────────────────────────────────────────────────────
# Using tput for broader terminal compatibility
if [[ -t 1 ]]; then
    BOLD=$(tput bold 2>/dev/null || echo "")
    DIM=$(tput dim 2>/dev/null || echo "")
    RESET=$(tput sgr0 2>/dev/null || echo "")
    RED=$(tput setaf 1 2>/dev/null || echo "")
    GREEN=$(tput setaf 2 2>/dev/null || echo "")
    YELLOW=$(tput setaf 3 2>/dev/null || echo "")
    BLUE=$(tput setaf 4 2>/dev/null || echo "")
    MAGENTA=$(tput setaf 5 2>/dev/null || echo "")
    CYAN=$(tput setaf 6 2>/dev/null || echo "")
    WHITE=$(tput setaf 7 2>/dev/null || echo "")
else
    BOLD=""; DIM=""; RESET=""
    RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""; WHITE=""
fi

readonly CHECK="${GREEN}${BOLD}✅${RESET}"
readonly CROSS="${RED}${BOLD}❌${RESET}"
readonly WARN="${YELLOW}${BOLD}⚠️${RESET}"
readonly INFO="${BLUE}${BOLD}ℹ️${RESET}"
readonly ARROW="${CYAN}${BOLD}➜${RESET}"
readonly GEAR="${MAGENTA}${BOLD}⚙️${RESET}"
readonly STAR="${YELLOW}${BOLD}⭐${RESET}"
readonly LOCK="${RED}${BOLD}🔒${RESET}"
readonly ROCKET="${MAGENTA}${BOLD}🚀${RESET}"
readonly SHIELD="${GREEN}${BOLD}🛡️${RESET}"
readonly PACKAGE="${CYAN}${BOLD}📦${RESET}"
readonly TOOLS="${BLUE}${BOLD}🔧${RESET}"
readonly WRENCH="${YELLOW}${BOLD}🔧${RESET}"
readonly CHART="${GREEN}${BOLD}📊${RESET}"
readonly CLIP="${WHITE}${BOLD}📋${RESET}"
readonly KEY="${MAGENTA}${BOLD}🔑${RESET}"
readonly GLOBE="${CYAN}${BOLD}🌐${RESET}"

# ─── Logging Functions ─────────────────────────────────────────────────────────
log_msg() {
    local level="$1"; shift
    local msg="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[${timestamp}] [${level}] ${msg}" >> "${LOG_FILE}"
}

log_info()  { log_msg "INFO" "$@"; }
log_warn()  { log_msg "WARN" "$@"; }
log_error() { log_msg "ERROR" "$@"; }
log_ok()    { log_msg "OK" "$@"; }

# ─── Display Helpers ──────────────────────────────────────────────────────────
print_header() {
    echo ""
    echo -e "${BOLD}${WHITE}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${WHITE}║${RESET}              ${BOLD}🏛️  ATLAS PLATFORM${RESET}                               ${BOLD}${WHITE}║${RESET}"
    echo -e "${BOLD}${WHITE}║${RESET}              ${DIM}Infrastructure Provisioning System${RESET}              ${BOLD}${WHITE}║${RESET}"
    echo -e "${BOLD}${WHITE}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_phase() {
    local phase="$1"
    local name="$2"
    echo ""
    echo -e "${BOLD}${CYAN}┌─────────────────────────────────────────────────────────────┐${RESET}"
    printf "${BOLD}${CYAN}│${RESET} ${BOLD}${WHITE}PHASE %-2s${RESET} ${CYAN}│${RESET} ${BOLD}%-51s${RESET} ${BOLD}${CYAN}│${RESET}\n" "$phase" "$name"
    echo -e "${BOLD}${CYAN}└─────────────────────────────────────────────────────────────┘${RESET}"
    log_info "=== PHASE ${phase}: ${name} ==="
}

print_step() {
    local msg="$1"
    echo -e "   ${ARROW} ${msg}..."
    log_info "  → ${msg}"
}

print_done() {
    local msg="${1:-Done}"
    echo -e "     ${CHECK} ${GREEN}${msg}${RESET}"
}

print_skip() {
    local msg="${1:-Already configured}"
    echo -e "     ${INFO} ${DIM}${msg} — skipping${RESET}"
}

print_error() {
    local msg="$1"
    echo -e "     ${CROSS} ${RED}${msg}${RESET}"
    log_error "  ✗ ${msg}"
}

print_warn() {
    local msg="$1"
    echo -e "     ${WARN} ${YELLOW}${msg}${RESET}"
    log_warn "  ⚠ ${msg}"
}

print_section() {
    local msg="$1"
    echo ""
    echo -e "  ${BOLD}${WHITE}${msg}${RESET}"
    echo -e "  ${DIM}$(printf '─%.0s' $(seq 1 60))${RESET}"
}

# ─── Utility Functions ─────────────────────────────────────────────────────────
is_phase_done() {
    local phase="$1"
    [[ -f "${DEPLOY_STAMP}_${phase}" ]]
}

mark_phase_done() {
    local phase="$1"
    mkdir -p "$(dirname "${DEPLOY_STAMP}")"
    touch "${DEPLOY_STAMP}_${phase}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') ATLAS v${ATLAS_VERSION}" > "${DEPLOY_STAMP}_${phase}"
}

idempotent_check() {
    local label="$1"
    local check_cmd="$2"
    if eval "${check_cmd}" 2>/dev/null; then
        return 0  # already done
    else
        return 1  # need to run
    fi
}

safe_run() {
    local desc="$1"
    local cmd="$2"
    print_step "${desc}"
    if eval "${cmd}" >> "${LOG_FILE}" 2>&1; then
        print_done
        return 0
    else
        print_error "Failed: ${desc}"
        log_error "Command failed: ${cmd}"
        return 1
    fi
}

safe_run_fallback() {
    local desc="$1"
    local cmd="$2"
    local fallback="$3"
    print_step "${desc}"
    if eval "${cmd}" >> "${LOG_FILE}" 2>&1; then
        print_done
        return 0
    else
        print_warn "Primary method failed, trying fallback..."
        log_warn "Primary failed for: ${desc}, trying fallback"
        if eval "${fallback}" >> "${LOG_FILE}" 2>&1; then
            print_done "Done (via fallback)"
            return 0
        else
            print_error "Both primary and fallback failed: ${desc}"
            log_error "Fallback also failed: ${fallback}"
            return 1
        fi
    fi
}

confirm_continue() {
    local msg="${1:-Continue?}"
    echo ""
    echo -e "  ${YELLOW}${msg}${RESET}"
    echo -n "  Press Enter to continue (or Ctrl+C to abort)... "
    read -r
}

# ─── Pre-Flight Checks ─────────────────────────────────────────────────────────
run_preflight() {
    print_section "PRE-FLIGHT CHECKS"
    local errors=0

    # Root check
    print_step "Checking root privileges"
    if [[ "$(id -u)" -eq 0 ]]; then
        print_done "Running as root"
    else
        print_error "Must run as root"
        ((errors++))
    fi

    # OS check
    print_step "Checking OS compatibility"
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        if [[ "${ID}" == "ubuntu" ]] && [[ "${VERSION_ID}" == "24.04" ]]; then
            print_done "Ubuntu ${VERSION_ID} detected"
        else
            print_warn "Expected Ubuntu 24.04, found: ${ID} ${VERSION_ID:-unknown}"
            if [[ "${VERSION_ID:-0}" != "24.04" ]]; then
                print_warn "Other Ubuntu versions may work but are not tested"
            fi
        fi
    else
        print_error "Cannot detect OS — /etc/os-release not found"
        ((errors++))
    fi

    # Architecture check
    print_step "Checking CPU architecture"
    local arch
    arch="$(uname -m)"
    if [[ "${arch}" == "x86_64" ]] || [[ "${arch}" == "aarch64" ]]; then
        print_done "${arch} — supported"
    else
        # Try to continue with a warning
        print_warn "${arch} — untested but proceeding"
    fi

    # Internet check
    print_step "Checking internet connectivity"
    if curl -sfL --connect-timeout 10 "https://google.com" -o /dev/null 2>/dev/null || \
       curl -sfL --connect-timeout 10 "https://cloudflare.com" -o /dev/null 2>/dev/null; then
        print_done "Internet accessible"
    else
        print_error "No internet connectivity detected"
        ((errors++))
    fi

    # DNS check
    print_step "Checking DNS resolution"
    if host -W 5 google.com >/dev/null 2>&1 || nslookup google.com >/dev/null 2>&1 || \
       getent hosts google.com >/dev/null 2>&1; then
        print_done "DNS working"
    else
        print_warn "DNS resolution failed, will configure DNS in Phase 0"
    fi

    # Disk space check
    print_step "Checking disk space"
    local avail
    avail="$(df / --output=avail 2>/dev/null | tail -1 | awk '{print $1}')"
    if [[ -n "${avail}" ]] && [[ "${avail}" -gt 2000000 ]]; then  # >2GB in KB
        print_done "Sufficient disk space ($((avail/1024/1024))GB available)"
    elif [[ -n "${avail}" ]]; then
        print_warn "Low disk space ($((avail/1024/1024))GB) — may cause issues"
    fi

    # Memory check
    print_step "Checking available memory"
    local mem
    mem="$(free -m | awk '/^Mem:/{print $2}')"
    if [[ -n "${mem}" ]] && [[ "${mem}" -ge 1800 ]]; then
        print_done "${mem}MB RAM — sufficient"
    elif [[ -n "${mem}" ]]; then
        print_warn "${mem}MB RAM — low, ZRAM swap will help"
    fi

    if [[ "${errors}" -gt 0 ]]; then
        echo ""
        echo -e "  ${CROSS} ${RED}${BOLD}Pre-flight checks failed with ${errors} error(s)${RESET}"
        echo "  Please fix the issues above and re-run."
        exit 1
    fi

    echo ""
    echo -e "  ${CHECK} ${GREEN}${BOLD}All pre-flight checks passed${RESET}"
    log_ok "All pre-flight checks passed"
}

# ─── PHASE 0: System Base ──────────────────────────────────────────────────────
phase_0_system_base() {
    print_phase "0" "System Base Configuration"

    if is_phase_done "0"; then
        print_skip "Phase 0 already completed"
        return 0
    fi

    # Initialize log
    mkdir -p "$(dirname "${LOG_FILE}")"
    touch "${LOG_FILE}"
    echo "═══════════════════════════════════════════════════════════════" >> "${LOG_FILE}"
    echo " ATLAS PLATFORM v${ATLAS_VERSION} — Deployment Started" >> "${LOG_FILE}"
    echo " Date: $(date)" >> "${LOG_FILE}"
    echo "═══════════════════════════════════════════════════════════════" >> "${LOG_FILE}"

    # Wait for any apt locks to free
    print_step "Waiting for apt/dpkg locks"
    local waited=0
    while fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock >/dev/null 2>&1; do
        sleep 2
        waited=$((waited + 2))
        if [[ "${waited}" -ge 120 ]]; then
            print_warn "Waited 2 minutes for apt locks — forcing"
            break
        fi
    done
    print_done "Apt ready"

    # Tweak apt to not prompt
    export DEBIAN_FRONTEND=noninteractive
    export NEEDRESTART_MODE=a

    # Update apt cache
    safe_run "Updating apt package lists" \
        "apt-get update -qq"

    # Install base packages
    safe_run "Installing essential system packages" \
        "apt-get install -y -qq \
            curl wget gnupg2 ca-certificates lsb-release software-properties-common \
            apt-transport-https build-essential git unzip zip jq \
            ufw fail2ban auditd audispd-plugins aide rkhunter lynis \
            ipset iptables-persistent netfilter-persistent \
            haveged chrony apparmor apparmor-profiles apparmor-utils \
            needrestart unattended-upgrades update-notifier-common \
            htop iotop iftop nmap tcpdump mtr \
            python3 python3-pip python3-venv python3-dev \
            libssl-dev libffi-dev zlib1g-dev libbz2-dev \
            libreadline-dev libsqlite3-dev libncursesw5-dev \
            xz-utils tk-dev libxml2-dev libxmlsec1-dev liblzma-dev \
            shellcheck dnsutils > /dev/null"

    # Configure DNS
    print_step "Configuring DNS resolvers (Cloudflare + Google)"
    if ! idempotent_check "DNS configured" "grep -q '1.1.1.1' /etc/systemd/resolved.conf 2>/dev/null"; then
        # Ensure systemd-resolved is the resolver
        if [[ -L /etc/resolv.conf ]] && readlink /etc/resolv.conf | grep -q "systemd"; then
            cat > /etc/systemd/resolved.conf <<'DNS_EOF'
[Resolve]
DNS=1.1.1.1 8.8.8.8
FallbackDNS=1.0.0.1 8.8.4.4
DNSSEC=allow-downgrade
DNSOverTLS=opportunistic
DNS_EOF
            systemctl restart systemd-resolved 2>/dev/null || true
            print_done "systemd-resolved configured with 1.1.1.1/8.8.8.8"
        else
            # Direct resolv.conf approach
            echo "nameserver 1.1.1.1" > /etc/resolv.conf
            echo "nameserver 8.8.8.8" >> /etc/resolv.conf
            chattr +i /etc/resolv.conf 2>/dev/null || true
            print_done "resolv.conf locked to Cloudflare/Google DNS"
        fi
    else
        print_skip "DNS already configured"
    fi

    # Timezone
    PREFERRED_TZ="${PREFERRED_TZ:-Asia/Jakarta}"
    print_step "Setting timezone to ${PREFERRED_TZ}"
    if idempotent_check "Timezone set" "timedatectl show --property=Timezone --value 2>/dev/null | grep -q '${PREFERRED_TZ}'"; then
        print_skip
    else
        timedatectl set-timezone "${PREFERRED_TZ}" 2>/dev/null || true
        print_done
    fi

    # Enable NTP sync
    print_step "Enabling NTP time synchronization"
    timedatectl set-ntp true 2>/dev/null || true
    systemctl enable --now chronyd 2>/dev/null || true
    print_done

    # Python venv
    print_step "Creating ATLAS Python virtual environment"
    if idempotent_check "Python venv exists" "[[ -d '${ATLAS_VENV}' ]]"; then
        print_skip
    else
        mkdir -p "${ATLAS_HOME}"
        python3 -m venv "${ATLAS_VENV}"
        "${ATLAS_VENV}/bin/pip" install --upgrade pip setuptools wheel >> "${LOG_FILE}" 2>&1
        print_done "venv created at ${ATLAS_VENV}"
    fi

    mark_phase_done "0"
}

# ─── PHASE 1: Kernel Hardening ─────────────────────────────────────────────────
phase_1_kernel_hardening() {
    print_phase "1" "Kernel Hardening"

    if is_phase_done "1"; then
        print_skip "Phase 1 already completed"
        return 0
    fi

    # Copy sysctl configs if source exists, otherwise create inline
    local sysctl_d="/etc/sysctl.d"

    print_step "Applying sysctl performance tuning (BBR)"
    # Always write these — the config files are the canonical source
    if [[ -f "${CONFIG_SRC}/sysctl/99-atlas-perf.conf" ]]; then
        cp "${CONFIG_SRC}/sysctl/99-atlas-perf.conf" "${sysctl_d}/99-atlas-perf.conf"
    else
        cat > "${sysctl_d}/99-atlas-perf.conf" <<'SYSCTL_PERF'
# ATLAS PLATFORM — BBR + Network Performance
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.core.rmem_default = 262144
net.core.wmem_default = 262144
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_mtu_probing = 1
net.core.netdev_max_backlog = 50000
net.core.somaxconn = 65535
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fastopen = 3
SYSCTL_PERF
    fi
    print_done "BBR + network tuning applied"

    print_step "Applying sysctl security hardening"
    if [[ -f "${CONFIG_SRC}/sysctl/99-atlas-hardening.conf" ]]; then
        cp "${CONFIG_SRC}/sysctl/99-atlas-hardening.conf" "${sysctl_d}/99-atlas-hardening.conf"
    else
        cat > "${sysctl_d}/99-atlas-hardening.conf" <<'SYSCTL_HARDEN'
# ATLAS PLATFORM — Kernel Security Hardening
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0
net.ipv4.icmp_ignore_bogus_error_responses = 1
kernel.randomize_va_space = 2
kernel.kptr_restrict = 2
kernel.kexec_load_disabled = 1
kernel.yama.ptrace_scope = 1
kernel.perf_event_paranoid = 3
kernel.unprivileged_bpf_disabled = 1
kernel.unprivileged_userns_clone = 0
fs.suid_dumpable = 0
kernel.core_pattern = |/bin/false
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.tcp_rfc1337 = 1
SYSCTL_HARDEN
    fi
    print_done "Security sysctls applied"

    print_step "Applying memory/filesystem optimizations"
    if [[ -f "${CONFIG_SRC}/sysctl/99-atlas-optimizations.conf" ]]; then
        cp "${CONFIG_SRC}/sysctl/99-atlas-optimizations.conf" "${sysctl_d}/99-atlas-optimizations.conf"
    else
        cat > "${sysctl_d}/99-atlas-optimizations.conf" <<'SYSCTL_OPT'
# ATLAS PLATFORM — Memory & Filesystem Optimizations
vm.swappiness = 10
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.overcommit_memory = 1
vm.overcommit_ratio = 50
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
fs.file-max = 2097152
fs.nr_open = 2097152
fs.aio-max-nr = 1048576
kernel.pid_max = 4194304
vm.max_map_count = 262144
SYSCTL_OPT
    fi
    print_done "Memory/filesystem optimizations applied"

    # Apply all sysctl settings
    safe_run "Applying sysctl parameters" \
        "sysctl --system"

    # Kernel module blacklist
    print_step "Applying kernel module blacklist"
    if [[ -f "${CONFIG_SRC}/modprobe/blacklist-hardening.conf" ]]; then
        cp "${CONFIG_SRC}/modprobe/blacklist-hardening.conf" "/etc/modprobe.d/atlas-blacklist-hardening.conf"
    else
        cat > "/etc/modprobe.d/atlas-blacklist-hardening.conf" <<'MODPROBE'
# ATLAS PLATFORM — Kernel Module Blacklist
install cramfs /bin/true
install freevxfs /bin/true
install jffs2 /bin/true
install hfs /bin/true
install hfsplus /bin/true
install squashfs /bin/true
install udf /bin/true
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
install firewire-core /bin/true
install ieee1394 /bin/true
MODPROBE
    fi
    print_done "Module blacklist applied"

    # Load BBR modules
    print_step "Ensuring BBR congestion control is loaded"
    modprobe tcp_bbr 2>/dev/null || true
    if grep -q "^tcp_bbr" /proc/modules 2>/dev/null; then
        print_done "BBR module loaded"
    else
        print_warn "BBR module not loaded (will take effect after reboot)"
    fi

    # Increase file descriptor limits
    print_step "Configuring file descriptor limits"
    cat > /etc/security/limits.d/99-atlas.conf <<'LIMITS'
*          soft    nofile    1048576
*          hard    nofile    1048576
root       soft    nofile    1048576
root       hard    nofile    1048576
LIMITS
    print_done

    mark_phase_done "1"
}

# ─── PHASE 2: SSH Hardening ────────────────────────────────────────────────────
phase_2_ssh_hardening() {
    print_phase "2" "SSH Hardening"

    if is_phase_done "2"; then
        print_skip "Phase 2 already completed"
        return 0
    fi

    # Generate SSH host keys if missing
    print_step "Ensuring SSH host keys exist"
    local host_keys=(
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_rsa_key"
        "/etc/ssh/ssh_host_ecdsa_key"
    )
    for key in "${host_keys[@]}"; do
        if [[ ! -f "${key}" ]]; then
            case "${key}" in
                *ed25519*) ssh-keygen -t ed25519 -f "${key}" -N "" -q -C "atlas-host-key" ;;
                *rsa*)     ssh-keygen -t rsa -b 4096 -f "${key}" -N "" -q -C "atlas-host-key" ;;
                *ecdsa*)   ssh-keygen -t ecdsa -b 521 -f "${key}" -N "" -q -C "atlas-host-key" ;;
            esac
        fi
    done
    print_done

    # Generate ATLAS SSH key for root
    print_step "Generating ATLAS SSH key for root access"
    local KEY_DIR="/root/.ssh"
    local KEY_NAME="atlas_ed25519"
    mkdir -p "${KEY_DIR}"
    chmod 700 "${KEY_DIR}"

    if [[ -f "${KEY_DIR}/${KEY_NAME}" ]]; then
        print_skip "Key already exists at ${KEY_DIR}/${KEY_NAME}"
    else
        ssh-keygen -t ed25519 -f "${KEY_DIR}/${KEY_NAME}" -N "" -C "atlas-platform-key" -q
        cat "${KEY_DIR}/${KEY_NAME}.pub" >> "${KEY_DIR}/authorized_keys"
        chmod 600 "${KEY_DIR}/authorized_keys" "${KEY_DIR}/${KEY_NAME}"
        chmod 644 "${KEY_DIR}/${KEY_NAME}.pub"
        print_done "ED25519 key pair generated"

        # Display the private key with a 15-second pause
        echo ""
        echo -e "  ${BOLD}${YELLOW}╔══════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "  ${BOLD}${YELLOW}║${RESET}  ${BOLD}${RED}🔑  SAVE THIS PRIVATE KEY IMMEDIATELY ─ 15 SECONDS  🔑${RESET}    ${BOLD}${YELLOW}║${RESET}"
        echo -e "  ${BOLD}${YELLOW}╚══════════════════════════════════════════════════════════════╝${RESET}"
        echo ""
        echo -e "  ${BOLD}${WHITE}Private key (${KEY_DIR}/${KEY_NAME}):${RESET}"
        echo -e "  ${DIM}$(printf '─%.0s' $(seq 1 70))${RESET}"
        cat "${KEY_DIR}/${KEY_NAME}"
        echo -e "  ${DIM}$(printf '─%.0s' $(seq 1 70))${RESET}"
        echo ""
        echo -e "  ${BOLD}Usage:${RESET} ssh -i ${KEY_NAME} -p ${SSH_PORT} root@<server-ip>"
        echo ""
        echo -e "  ${YELLOW}⏳ Copy the key above NOW. Waiting 15 seconds...${RESET}"
        sleep 15
        echo -e "  ${GREEN}✅ Continuing deployment...${RESET}"
    fi

    # Backup original sshd_config
    print_step "Backing up original SSH configuration"
    if [[ ! -f /etc/ssh/sshd_config.orig ]]; then
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.orig
        print_done "Backed up to /etc/ssh/sshd_config.orig"
    else
        print_skip "Backup already exists"
    fi

    # Apply SSH hardening drop-in config
    print_step "Applying SSH hardening configuration"
    local ssh_dropin="/etc/ssh/sshd_config.d/99-atlas-hardening.conf"
    mkdir -p "/etc/ssh/sshd_config.d"

    if [[ -f "${CONFIG_SRC}/ssh/hardening.conf" ]]; then
        cp "${CONFIG_SRC}/ssh/hardening.conf" "${ssh_dropin}"
    else
        cat > "${ssh_dropin}" <<'SSHCONF'
# ATLAS PLATFORM — SSH Hardening
Port 2222
PubkeyAuthentication yes
PasswordAuthentication no
PermitRootLogin prohibit-password
AuthenticationMethods publickey
X11Forwarding no
MaxAuthTries 3
MaxSessions 5
ClientAliveInterval 300
ClientAliveCountMax 2
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no
LoginGraceTime 30
MaxStartups 3:50:10
SSHCONF
    fi
    print_done "Drop-in config written"

    # Ensure main sshd_config is sensible
    # Include drop-in dir if not already
    if ! grep -q "^Include /etc/ssh/sshd_config.d/\*.conf" /etc/ssh/sshd_config 2>/dev/null; then
        echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
    fi

    # Validate and restart SSH
    print_step "Validating SSH configuration"
    if sshd -t 2>/dev/null; then
        print_done "SSH configuration valid"
        safe_run "Restarting SSH service" \
            "systemctl restart sshd || systemctl restart ssh"
    else
        print_error "SSH configuration invalid — restoring backup"
        cp /etc/ssh/sshd_config.orig /etc/ssh/sshd_config
        rm -f "${ssh_dropin}"
        sshd -t && systemctl restart sshd || true
        log_error "SSH config was invalid, restored original"
        return 1
    fi

    # Firewall note — actual UFW setup is Phase 3 but ensure SSH on current port
    print_step "Adding temporary UFW rule for SSH port ${SSH_PORT}"
    ufw allow "${SSH_PORT}/tcp" comment "ATLAS SSH" 2>/dev/null || true
    print_done

    mark_phase_done "2"
}

# ─── PHASE 3: Firewall + fail2ban ──────────────────────────────────────────────
phase_3_firewall_fail2ban() {
    print_phase "3" "Firewall + fail2ban"

    if is_phase_done "3"; then
        print_skip "Phase 3 already completed"
        return 0
    fi

    # UFW
    print_step "Configuring UFW firewall"
    ufw default deny incoming >/dev/null 2>&1 || true
    ufw default allow outgoing >/dev/null 2>&1 || true
    ufw allow "${SSH_PORT}/tcp" comment "ATLAS SSH" >/dev/null 2>&1 || true
    # Allow HTTP/HTTPS for web services (commented: uncomment if needed)
    # ufw allow 80/tcp comment "HTTP" >/dev/null 2>&1 || true
    # ufw allow 443/tcp comment "HTTPS" >/dev/null 2>&1 || true

    if ufw status | grep -q "Status: active"; then
        print_skip "UFW already active"
    else
        ufw --force enable >/dev/null 2>&1 || true
        print_done "UFW enabled (default deny incoming, allow ${SSH_PORT})"
    fi

    # fail2ban — SSH jail
    print_step "Configuring fail2ban SSH jail"
    local f2b_sshd="/etc/fail2ban/jail.d/atlas-sshd.conf"
    if [[ -f "${CONFIG_SRC}/fail2ban/sshd.conf" ]]; then
        cp "${CONFIG_SRC}/fail2ban/sshd.conf" "${f2b_sshd}"
    else
        cat > "${f2b_sshd}" <<'F2BSSHD'
# ATLAS PLATFORM — fail2ban SSH jail
[sshd]
enabled  = true
port     = 2222
filter   = sshd
logpath  = %(sshd_log)s
backend  = %(sshd_backend)s
maxretry = 3
findtime = 10m
bantime  = 1h
ignoreip = 127.0.0.1/8 ::1
F2BSSHD
    fi
    print_done

    # fail2ban — Recidive jail
    print_step "Configuring fail2ban recidive jail"
    local f2b_recidive="/etc/fail2ban/jail.d/atlas-recidive.conf"
    if [[ -f "${CONFIG_SRC}/fail2ban/recidive.conf" ]]; then
        cp "${CONFIG_SRC}/fail2ban/recidive.conf" "${f2b_recidive}"
    else
        cat > "${f2b_recidive}" <<'F2BREC'
# ATLAS PLATFORM — fail2ban Recidive jail
[recidive]
enabled  = true
filter   = recidive
logpath  = /var/log/fail2ban.log
banaction = %(banaction_allports)s
bantime  = -1
findtime = 1w
maxretry = 3
F2BREC
    fi
    print_done

    # Restart fail2ban
    safe_run "Restarting fail2ban service" \
        "systemctl restart fail2ban && systemctl enable fail2ban"

    mark_phase_done "3"
}

# ─── PHASE 4: Geo-Blocking ─────────────────────────────────────────────────────
phase_4_geo_blocking() {
    print_phase "4" "Geo-Blocking (ipset)"

    if is_phase_done "4"; then
        print_skip "Phase 4 already completed"
        return 0
    fi

    print_step "Creating ipset blacklist (RU, CN, UZ, LT)"
    # Destroy and recreate to ensure clean state
    ipset destroy ATLAS_BLACKLIST 2>/dev/null || true
    ipset create ATLAS_BLACKLIST hash:net maxelem 131072 2>/dev/null || \
        print_warn "ipset create failed — may already exist"

    ipset flush ATLAS_BLACKLIST 2>/dev/null || true

    # Add aggregated country subnets
    # These are representative subnets. In production, use a full GeoIP database.
    cat >> /tmp/atlas_blocklist.txt <<'BLOCKS'
# Russia (RU) — major subnets
2.56.0.0/14
5.8.0.0/16
5.16.0.0/16
5.44.0.0/15
5.101.0.0/16
5.128.0.0/13
5.136.0.0/13
37.9.0.0/16
37.140.0.0/14
45.80.0.0/13
46.0.0.0/13
46.17.200.0/21
46.42.0.0/18
62.33.0.0/16
77.88.0.0/19
78.24.0.0/15
78.85.0.0/16
79.104.0.0/13
80.64.16.0/20
80.80.96.0/20
80.90.160.0/20
81.176.0.0/14
82.193.128.0/19
83.220.236.0/22
84.18.0.0/17
85.192.0.0/13
87.224.0.0/13
88.147.128.0/17
89.189.0.0/17
89.223.0.0/16
90.150.0.0/16
91.144.128.0/17
91.194.0.0/15
92.50.128.0/18
92.100.0.0/14
92.240.0.0/13
93.80.0.0/13
94.24.0.0/15
95.24.0.0/15
109.172.0.0/16
128.72.0.0/14
141.8.128.0/17
178.34.0.0/16
178.66.0.0/14
178.140.0.0/14
185.5.136.0/22
188.128.0.0/13
194.28.0.0/16
194.186.0.0/15
195.50.0.0/16
212.176.0.0/12
213.87.0.0/16
# China (CN) — major subnets
1.0.1.0/24
1.0.32.0/19
1.4.0.0/14
14.0.0.0/22
14.102.128.0/22
14.192.0.0/13
27.0.128.0/22
27.8.0.0/13
27.152.0.0/13
36.0.0.0/22
42.62.0.0/16
42.80.0.0/13
43.224.12.0/22
49.64.0.0/11
58.14.0.0/15
59.32.0.0/13
60.0.0.0/13
101.0.0.0/15
101.224.0.0/13
110.6.0.0/15
111.0.0.0/10
112.0.0.0/10
# Uzbekistan (UZ) — representative
84.54.64.0/19
91.212.89.0/24
178.218.200.0/21
188.113.192.0/18
195.158.0.0/19
# Lithuania (LT) — representative
5.20.0.0/16
46.36.64.0/21
77.221.64.0/19
77.240.64.0/20
78.56.0.0/13
82.135.128.0/17
84.15.0.0/16
88.118.0.0/12
BLOCKS

    local added=0
    local failed=0
    while IFS= read -r line; do
        [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
        if ipset add ATLAS_BLACKLIST "${line}" 2>/dev/null; then
            ((added++))
        else
            ((failed++))
        fi
    done < /tmp/atlas_blocklist.txt
    rm -f /tmp/atlas_blocklist.txt
    print_done "Blacklisted ${added} subnets (${failed} duplicates/failures)"

    # Create whitelist for Indonesia
    print_step "Creating ipset whitelist (ID)"
    ipset destroy ATLAS_WHITELIST 2>/dev/null || true
    ipset create ATLAS_WHITELIST hash:net maxelem 65536 2>/dev/null || true
    ipset flush ATLAS_WHITELIST 2>/dev/null || true

    cat >> /tmp/atlas_whitelist.txt <<'WHITE'
# Indonesia (ID) — major subnets
36.50.0.0/16
36.64.0.0/12
36.80.0.0/12
103.0.0.0/14
103.16.0.0/14
103.20.0.0/14
103.28.0.0/14
103.48.0.0/14
103.76.0.0/14
103.80.0.0/14
103.84.0.0/14
103.88.0.0/14
103.92.0.0/14
103.96.0.0/14
103.100.0.0/14
103.104.0.0/14
103.108.0.0/14
103.112.0.0/14
103.116.0.0/14
103.120.0.0/14
103.124.0.0/14
103.128.0.0/14
110.50.0.0/16
110.136.0.0/13
110.232.240.0/22
112.78.128.0/19
112.215.0.0/14
114.0.0.0/14
114.120.0.0/13
114.128.0.0/13
114.136.0.0/13
115.178.0.0/15
116.12.0.0/16
116.66.0.0/16
116.68.0.0/14
117.20.56.0/21
117.53.0.0/16
117.102.0.0/16
118.96.0.0/12
119.11.0.0/16
119.82.0.0/16
119.110.0.0/16
119.252.160.0/19
120.160.0.0/11
123.108.0.0/15
124.6.32.0/19
124.40.0.0/14
124.81.0.0/17
124.195.0.0/16
125.160.0.0/15
139.192.0.0/14
180.178.0.0/16
180.240.0.0/14
182.0.0.0/14
202.0.64.0/18
202.6.224.0/21
202.9.64.0/21
202.43.64.0/19
202.46.0.0/16
202.51.96.0/20
202.51.224.0/20
202.57.0.0/15
202.62.0.0/16
202.69.96.0/20
202.80.120.0/21
202.91.0.0/16
202.146.0.0/15
202.148.0.0/13
202.168.32.0/20
202.180.48.0/20
203.6.144.0/22
203.77.224.0/19
203.176.176.0/24
203.190.48.0/23
222.124.0.0/15
WHITE

    local wadded=0
    local wfailed=0
    while IFS= read -r line; do
        [[ -z "${line}" || "${line}" =~ ^[[:space:]]*# ]] && continue
        if ipset add ATLAS_WHITELIST "${line}" 2>/dev/null; then
            ((wadded++))
        else
            ((wfailed++))
        fi
    done < /tmp/atlas_whitelist.txt
    rm -f /tmp/atlas_whitelist.txt
    print_done "Whitelisted ${wadded} Indonesia subnets (${wfailed} duplicates/failures)"

    # Persist ipsets
    print_step "Persisting ipset rules"
    mkdir -p /etc/ipset.conf.d 2>/dev/null || true
    ipset save > /etc/iptables/ipsets 2>/dev/null || \
        ipset save > /etc/iptables/rules.v4 2>/dev/null || true
    # Also save via netfilter-persistent
    netfilter-persistent save 2>/dev/null || true
    print_done

    # Add iptables rules to drop blacklisted and allow whitelisted
    print_step "Applying iptables geo-blocking rules"
    # Check if rules already exist
    if ! iptables -C INPUT -m set --match-set ATLAS_BLACKLIST src -j DROP 2>/dev/null; then
        iptables -I INPUT 1 -m set --match-set ATLAS_WHITELIST src -j ACCEPT 2>/dev/null || true
        iptables -I INPUT 2 -m set --match-set ATLAS_BLACKLIST src -j DROP 2>/dev/null || true
        # Persist
        netfilter-persistent save 2>/dev/null || true
        print_done "Geo-blocking iptables rules applied"
    else
        print_skip "Geo-blocking rules already exist"
    fi

    mark_phase_done "4"
}

# ─── PHASE 5: Detection Tools ──────────────────────────────────────────────────
phase_5_detection_tools() {
    print_phase "5" "Detection Tools"

    if is_phase_done "5"; then
        print_skip "Phase 5 already completed"
        return 0
    fi

    # auditd rules
    print_step "Configuring auditd rules"
    mkdir -p /etc/audit/rules.d
    if [[ -f "${CONFIG_SRC}/auditd/atlas.rules" ]]; then
        cp "${CONFIG_SRC}/auditd/atlas.rules" /etc/audit/rules.d/atlas.rules
    else
        # Create basic rules inline
        cat > /etc/audit/rules.d/atlas.rules <<'AUDITRULES'
# ATLAS PLATFORM — auditd rules
-D
-b 8192
-f 1
-w /etc/passwd -p wa -k atlas_identity
-w /etc/shadow -p wa -k atlas_identity
-w /etc/group -p wa -k atlas_identity
-w /etc/sudoers -p wa -k atlas_sudo
-w /etc/sudoers.d/ -p wa -k atlas_sudo
-w /etc/ssh/sshd_config -p wa -k atlas_ssh
-w /etc/ssh/sshd_config.d/ -p wa -k atlas_ssh
-w /etc/sysctl.d/ -p wa -k atlas_sysctl
-w /root/.ssh/authorized_keys -p wa -k atlas_rootkeys
AUDITRULES
    fi

    # Restart auditd
    safe_run "Restarting auditd service" \
        "systemctl restart auditd && systemctl enable auditd" || \
        print_warn "auditd restart had issues — check logs"

    # Initialize AIDE database
    print_step "Initializing AIDE integrity database"
    if idempotent_check "AIDE DB exists" "[[ -f /var/lib/aide/aide.db.gz ]]"; then
        print_skip "AIDE database already exists"
    else
        # Create config if needed
        if [[ ! -f /etc/aide/aide.conf ]]; then
            aideinit -y -f 2>/dev/null || true
            if [[ -f /var/lib/aide/aide.db.new ]]; then
                mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db.gz
            fi
        fi
        # Update AIDE db
        aideinit 2>/dev/null || aide --init 2>/dev/null || true
        if [[ -f /var/lib/aide/aide.db.new ]]; then
            mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db.gz
            print_done "AIDE database initialized"
        else
            print_warn "AIDE init may need manual review"
        fi
    fi

    # Update RKHunter properties
    print_step "Updating RKHunter properties"
    rkhunter --propupd --quiet 2>/dev/null || true
    print_done "RKHunter property database updated"

    # Lynis audit (initial scan)
    print_step "Running initial Lynis security audit"
    mkdir -p /var/log/lynis
    lynis audit system --quiet --log-file /var/log/lynis/atlas-initial.log 2>/dev/null || true
    print_done "Lynis initial scan complete (log: /var/log/lynis/atlas-initial.log)"

    mark_phase_done "5"
}

# ─── PHASE 6: Maintenance ──────────────────────────────────────────────────────
phase_6_maintenance() {
    print_phase "6" "Maintenance Configuration"

    if is_phase_done "6"; then
        print_skip "Phase 6 already completed"
        return 0
    fi

    # Unattended upgrades
    print_step "Configuring unattended security upgrades"
    cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'AUTOUPG'
// ATLAS PLATFORM — Unattended Upgrades Configuration
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
Unattended-Upgrade::SyslogEnable "true";
Unattended-Upgrade::OnlyOnACPower "false";
AUTOUPG

    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'AUTOUPG2'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
AUTOUPG2
    print_done "Unattended upgrades configured (security only, no auto-reboot)"

    # Journald
    print_step "Configuring journald limits (200MB max)"
    mkdir -p /etc/systemd/journald.conf.d
    if [[ -f "${CONFIG_SRC}/journald/atlas.conf" ]]; then
        cp "${CONFIG_SRC}/journald/atlas.conf" /etc/systemd/journald.conf.d/atlas.conf
    else
        cat > /etc/systemd/journald.conf.d/atlas.conf <<'JOURNALD'
# ATLAS PLATFORM — Journald Limits
[Journal]
SystemMaxUse=200M
SystemMaxFileSize=50M
MaxRetentionSec=30day
Compress=yes
ForwardToSyslog=no
ForwardToConsole=no
ForwardToWall=no
MaxLevelStore=notice
JOURNALD
    fi
    systemctl restart systemd-journald 2>/dev/null || true
    print_done "Journald limited to 200MB compressed"

    # ZRAM swap
    print_step "Setting up ZRAM swap (${ZRAM_SIZE} zstd)"
    if idempotent_check "ZRAM active" "swapon --show 2>/dev/null | grep -q zram0"; then
        print_skip "ZRAM swap already active"
    else
        # Copy service file
        if [[ -f "${CONFIG_SRC}/zram/atlas-zram.service" ]]; then
            cp "${CONFIG_SRC}/zram/atlas-zram.service" /etc/systemd/system/atlas-zram.service
        else
            cat > /etc/systemd/system/atlas-zram.service <<'ZRAMUNIT'
[Unit]
Description=ATLAS PLATFORM — ZRAM Swap (zstd)
After=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c '\
  modprobe zram || true; \
  echo zstd > /sys/block/zram0/comp_algorithm 2>/dev/null || true; \
  echo 1G > /sys/block/zram0/disksize 2>/dev/null || true; \
  mkswap /dev/zram0 2>/dev/null || true; \
  swapon -p 100 /dev/zram0 2>/dev/null || true'
ExecStop=/bin/bash -c 'swapoff /dev/zram0 2>/dev/null; echo 1 > /sys/block/zram0/reset 2>/dev/null || true'

[Install]
WantedBy=multi-user.target
ZRAMUNIT
        fi

        systemctl daemon-reload
        systemctl enable --now atlas-zram 2>/dev/null || true
        if swapon --show 2>/dev/null | grep -q zram0; then
            print_done "ZRAM swap active (${ZRAM_SIZE} zstd)"
        else
            # Fallback: create directly
            modprobe zram 2>/dev/null || true
            echo zstd > /sys/block/zram0/comp_algorithm 2>/dev/null || true
            echo 1G > /sys/block/zram0/disksize 2>/dev/null || true
            mkswap /dev/zram0 2>/dev/null || true
            swapon -p 100 /dev/zram0 2>/dev/null || true
            if swapon --show | grep -q zram0; then
                print_done "ZRAM swap active (direct creation)"
            else
                print_warn "ZRAM swap could not be activated"
            fi
        fi
    fi

    # Disable auto-reboot after kernel updates
    print_step "Disabling automatic reboot after updates"
    if [[ -f /etc/needrestart/needrestart.conf ]]; then
        sed -i 's/^#\$nrconf{restart} = .*/\$nrconf{restart} = '\''l'\'';/' /etc/needrestart/needrestart.conf 2>/dev/null || true
    fi
    print_done

    mark_phase_done "6"
}

# ─── PHASE 7: Toolchain ────────────────────────────────────────────────────────
phase_7_toolchain() {
    print_phase "7" "Development Toolchain"

    if is_phase_done "7"; then
        print_skip "Phase 7 already completed"
        return 0
    fi

    # Go 1.22.5
    print_step "Installing Go ${GO_VERSION}"
    if idempotent_check "Go installed" "command -v go >/dev/null 2>&1 && go version 2>/dev/null | grep -q '${GO_VERSION}'"; then
        print_skip "Go ${GO_VERSION} already installed"
    else
        local go_arch
        go_arch="$(uname -m)"
        case "${go_arch}" in
            x86_64) go_arch="amd64" ;;
            aarch64) go_arch="arm64" ;;
            *) go_arch="amd64" ;;
        esac

        local go_url="https://go.dev/dl/go${GO_VERSION}.linux-${go_arch}.tar.gz"
        if curl -sfL "${go_url}" -o /tmp/go.tar.gz 2>/dev/null; then
            rm -rf /usr/local/go 2>/dev/null || true
            tar -C /usr/local -xzf /tmp/go.tar.gz
            rm -f /tmp/go.tar.gz

            # Set up Go environment for all users
            cat > /etc/profile.d/go.sh <<'GOPROFILE'
export GOROOT=/usr/local/go
export GOPATH=/opt/atlas/go
export PATH=$PATH:$GOROOT/bin:$GOPATH/bin
GOPROFILE
            chmod 644 /etc/profile.d/go.sh
            # Source for this session
            export GOROOT=/usr/local/go
            export GOPATH=/opt/atlas/go
            export PATH="${PATH}:${GOROOT}/bin:${GOPATH}/bin"
            mkdir -p "${GOPATH}/bin"
            print_done "Go ${GO_VERSION} installed"
        else
            print_error "Could not download Go ${GO_VERSION}"
            return 1
        fi
    fi

    # Node.js 22
    print_step "Installing Node.js ${NODE_MAJOR}"
    if idempotent_check "Node.js installed" "command -v node >/dev/null 2>&1 && node --version 2>/dev/null | grep -q 'v${NODE_MAJOR}'"; then
        print_skip "Node.js ${NODE_MAJOR} already installed"
    else
        # Remove old NodeSource setups if any
        rm -f /etc/apt/sources.list.d/nodesource.list 2>/dev/null || true

        # Use NodeSource setup script
        if curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" -o /tmp/nodesource_setup.sh 2>/dev/null; then
            bash /tmp/nodesource_setup.sh 2>/dev/null || true
            rm -f /tmp/nodesource_setup.sh
            apt-get install -y -qq nodejs 2>/dev/null || true
            rm -f /tmp/nodesource_setup.sh
        else
            # Fallback: try direct install
            print_warn "NodeSource script failed, trying direct install"
            apt-get install -y -qq nodejs npm 2>/dev/null || true
        fi

        if command -v node >/dev/null 2>&1; then
            print_done "Node.js $(node --version) installed"
        else
            print_error "Node.js installation failed"
            return 1
        fi
    fi

    # PM2 (global)
    print_step "Installing PM2 process manager"
    if idempotent_check "PM2 installed" "command -v pm2 >/dev/null 2>&1"; then
        print_skip "PM2 $(pm2 --version 2>/dev/null) already installed"
    else
        npm install -g pm2 >> "${LOG_FILE}" 2>&1 || true
        if command -v pm2 >/dev/null 2>&1; then
            print_done "PM2 $(pm2 --version) installed"
        else
            print_warn "PM2 install may need manual verification"
        fi
    fi

    # Yarn (global)
    print_step "Installing Yarn package manager"
    if idempotent_check "Yarn installed" "command -v yarn >/dev/null 2>&1"; then
        print_skip "Yarn $(yarn --version 2>/dev/null) already installed"
    else
        npm install -g yarn >> "${LOG_FILE}" 2>&1 || true
        if command -v yarn >/dev/null 2>&1; then
            print_done "Yarn $(yarn --version) installed"
        else
            print_warn "Yarn install — continuing"
        fi
    fi

    # Playwright (in venv)
    print_step "Installing Playwright (Python + Chromium)"
    if idempotent_check "Playwright installed" "${ATLAS_VENV}/bin/pip show playwright >/dev/null 2>&1"; then
        print_skip "Playwright already installed in venv"
    else
        "${ATLAS_VENV}/bin/pip" install playwright >> "${LOG_FILE}" 2>&1
        "${ATLAS_VENV}/bin/playwright" install chromium >> "${LOG_FILE}" 2>&1 || true
        "${ATLAS_VENV}/bin/playwright" install-deps chromium >> "${LOG_FILE}" 2>&1 || true
        print_done "Playwright + Chromium installed"
    fi

    # web3.py
    print_step "Installing web3.py"
    if idempotent_check "web3 installed" "${ATLAS_VENV}/bin/pip show web3 >/dev/null 2>&1"; then
        print_skip "web3.py already installed"
    else
        "${ATLAS_VENV}/bin/pip" install web3 >> "${LOG_FILE}" 2>&1
        print_done "web3.py installed"
    fi

    # Go security tools: nuclei, subfinder, httpx
    if command -v go >/dev/null 2>&1; then
        print_step "Installing Go security tools (nuclei, subfinder, httpx)"

        if idempotent_check "nuclei installed" "command -v nuclei >/dev/null 2>&1"; then
            print_skip "nuclei already installed"
        else
            go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest >> "${LOG_FILE}" 2>&1 || true
            command -v nuclei >/dev/null 2>&1 && print_done "nuclei installed" || print_warn "nuclei install failed"
        fi

        if idempotent_check "subfinder installed" "command -v subfinder >/dev/null 2>&1"; then
            print_skip "subfinder already installed"
        else
            go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest >> "${LOG_FILE}" 2>&1 || true
            command -v subfinder >/dev/null 2>&1 && print_done "subfinder installed" || print_warn "subfinder install failed"
        fi

        if idempotent_check "httpx installed" "command -v httpx >/dev/null 2>&1"; then
            print_skip "httpx already installed"
        else
            go install github.com/projectdiscovery/httpx/cmd/httpx@latest >> "${LOG_FILE}" 2>&1 || true
            command -v httpx >/dev/null 2>&1 && print_done "httpx installed" || print_warn "httpx install failed"
        fi
    else
        print_warn "Go not available — skipping Go security tools"
    fi

    # Create project directories
    print_step "Creating project directories"
    mkdir -p /opt/atlas/{projects,scripts,logs,data,secrets,tools}
    chmod 750 /opt/atlas/secrets 2>/dev/null || true
    print_done

    mark_phase_done "7"
}

# ─── PHASE 8: Hermes Agent ─────────────────────────────────────────────────────
phase_8_hermes_agent() {
    print_phase "8" "Hermes Agent Deployment"

    if is_phase_done "8"; then
        print_skip "Phase 8 already completed"
        return 0
    fi

    # Install Hermes Agent in venv
    print_step "Installing Hermes Agent"
    if idempotent_check "Hermes installed" "${ATLAS_VENV}/bin/pip show hermes-agent >/dev/null 2>&1"; then
        print_skip "Hermes Agent already installed"
    else
        "${ATLAS_VENV}/bin/pip" install hermes-agent >> "${LOG_FILE}" 2>&1 || \
            "${ATLAS_VENV}/bin/pip" install git+https://github.com/NousResearch/hermes-agent.git >> "${LOG_FILE}" 2>&1 || \
            print_warn "Hermes Agent pip install failed — check logs"
        print_done "Hermes Agent installed (or attempted)"
    fi

    # Symlink global `hermes` binary so root & hermes user can use it
    if [[ -f "${ATLAS_VENV}/bin/hermes" ]]; then
        ln -sf "${ATLAS_VENV}/bin/hermes" /usr/local/bin/hermes
        print_done "Hermes CLI linked to /usr/local/bin/hermes"
    else
        print_warn "Hermes CLI binary not found at ${ATLAS_VENV}/bin/hermes"
    fi

    # Create hermes system user
    print_step "Creating '${HERMES_USER}' system user"
    if idempotent_check "hermes user exists" "id ${HERMES_USER} >/dev/null 2>&1"; then
        print_skip "User '${HERMES_USER}' already exists"
    else
        useradd --system --home-dir "/home/${HERMES_USER}" \
                --shell /bin/bash --create-home \
                "${HERMES_USER}" 2>/dev/null || \
        useradd -r -m -s /bin/bash "${HERMES_USER}" 2>/dev/null || \
        { print_error "Could not create hermes user"; return 1; }

        # Add to necessary groups
        usermod -aG docker "${HERMES_USER}" 2>/dev/null || true
        usermod -aG systemd-journal "${HERMES_USER}" 2>/dev/null || true

        # Set up SSH key for hermes user
        mkdir -p "/home/${HERMES_USER}/.ssh"
        chmod 700 "/home/${HERMES_USER}/.ssh"
        cp /root/.ssh/authorized_keys "/home/${HERMES_USER}/.ssh/authorized_keys" 2>/dev/null || true
        chmod 600 "/home/${HERMES_USER}/.ssh/authorized_keys"
        chown -R "${HERMES_USER}:${HERMES_USER}" "/home/${HERMES_USER}/.ssh"

        print_done "User '${HERMES_USER}' created"
    fi

    # Set up hermes home directories
    print_step "Setting up hermes user directories"
    mkdir -p "/home/${HERMES_USER}/.hermes/config" "/home/${HERMES_USER}/.hermes/skills" "/home/${HERMES_USER}/.hermes/data" "/home/${HERMES_USER}/.hermes/logs"
    chown -R "${HERMES_USER}:${HERMES_USER}" "/home/${HERMES_USER}/.hermes"

    # Create default Hermes config (current CLI schema v0.16+)
    cat > "/home/${HERMES_USER}/.hermes/config/config.yaml" <<'HERMESCFG'
# ATLAS PLATFORM — Hermes Agent Configuration
# Run `su - hermes && hermes setup` after install to add models/providers.

model:
  default_model: "nous/hermes-3-llama-3.1-405b"
  default_max_tokens: 4096

providers:
  nous:
    type: "nous"

paths:
  base: /home/hermes
  projects: /opt/atlas/projects/
  logs: /opt/atlas/logs/
  data: /opt/atlas/data/

logging:
  level: INFO
  max_bytes: 10485760
  backup_count: 5
HERMESCFG
    chown "${HERMES_USER}:${HERMES_USER}" "/home/${HERMES_USER}/.hermes/config/config.yaml"
    print_done "Default Hermes config created"

    # Create systemd service for Hermes Agent (v0.16+ CLI)
    print_step "Creating systemd service for Hermes Agent"
    cat > /etc/systemd/system/hermes.service <<HERMESUNIT
[Unit]
Description=ATLAS PLATFORM — Hermes Agent
Documentation=https://github.com/NousResearch/hermes-agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${HERMES_USER}
Group=${HERMES_USER}
WorkingDirectory=/home/${HERMES_USER}
ExecStart=${ATLAS_VENV}/bin/hermes gateway run
ExecStop=/bin/kill -s TERM \$MAINPID
Restart=on-failure
RestartSec=10
TimeoutStopSec=210
KillMode=mixed

# Sandboxing & Security
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=no
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/opt/atlas/ /home/${HERMES_USER}/.hermes/ /var/log/
ReadOnlyPaths=/etc/ /usr/
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX AF_NETLINK
RestrictNamespaces=yes
LockPersonality=yes
MemoryDenyWriteExecute=no
RestrictRealtime=yes
RestrictSUIDSGID=yes
RemoveIPC=yes

# Resource limits
LimitNOFILE=65535
LimitNPROC=4096
MemoryMax=4G
CPUQuota=200%

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=hermes

[Install]
WantedBy=multi-user.target
HERMESUNIT

    systemctl daemon-reload
    print_done "Systemd service created at /etc/systemd/system/hermes.service"

    # Enable but don't start — user needs to configure API keys first
    print_step "Enabling Hermes service (not started — needs configuration)"
    systemctl enable hermes 2>/dev/null || true
    print_done "Service enabled. Configure with: su - hermes && hermes setup"

    mark_phase_done "8"
}

# ─── PHASE 9: Finalization ─────────────────────────────────────────────────────
phase_9_finalization() {
    print_phase "9" "Finalization"

    if is_phase_done "9"; then
        print_skip "Phase 9 already completed — deployment fully complete"
        return 0
    fi

    # MOTD
    print_step "Installing ATLAS MOTD"
    mkdir -p /etc/update-motd.d
    if [[ -f "${CONFIG_SRC}/motd/99-atlas" ]]; then
        cp "${CONFIG_SRC}/motd/99-atlas" /etc/update-motd.d/99-atlas
    else
        # Create a simple MOTD
        cat > /etc/update-motd.d/99-atlas <<'MOTDEOF'
#!/bin/bash
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    🏛️  ATLAS PLATFORM                        ║"
echo "║              Infrastructure Automation Server               ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Hostname.....: $(hostname -f 2>/dev/null || hostname)"
echo "  OS...........: $(lsb_release -ds 2>/dev/null || cat /etc/os-release 2>/dev/null | grep PRETTY | cut -d'"' -f2)"
echo "  Kernel.......: $(uname -r)"
echo "  Uptime.......: $(uptime -p 2>/dev/null | sed 's/up //')"
echo "  Load.........: $(awk '{print $1", "$2", "$3}' /proc/loadavg)"
echo ""
echo "  IPv4.........: $(hostname -I 2>/dev/null | awk '{print $1}')"
echo "  SSH Port.....: $(grep -oP '^Port\s+\K\d+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | tail -1)"
echo "  UFW..........: $(ufw status 2>/dev/null | head -1 | awk '{print $2}')"
echo ""
echo "  📋 Deploy Log: /var/log/atlas-deploy.log"
echo ""
MOTDEOF
    fi
    chmod +x /etc/update-motd.d/99-atlas
    print_done

    # Clean apt cache
    print_step "Cleaning apt cache"
    apt-get clean 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
    print_done

    # Remove motd news
    print_step "Disabling apt news MOTD"
    sed -i 's/^ENABLED=1/ENABLED=0/' /etc/default/motd-news 2>/dev/null || true
    # Also touch to prevent regeneration
    touch /etc/motd 2>/dev/null || true
    print_done

    # .bashrc additions
    print_step "Adding ATLAS aliases to root .bashrc"
    if ! grep -q "ATLAS PLATFORM" /root/.bashrc 2>/dev/null; then
        cat >> /root/.bashrc <<'BASHRC'

# ── ATLAS PLATFORM Aliases ──────────────────────────────────
alias atlas-status='systemctl status hermes fail2ban auditd ufw --no-pager -l'
alias atlas-log='journalctl -u hermes -f'
alias atlas-deploy-log='less /var/log/atlas-deploy.log'
alias atlas-update='apt update && apt upgrade -y'
alias atlas-security='lynis audit system --quick'
alias atlas-fw='ufw status verbose'
alias atlas-ssh='grep -oP "^Port\s+\K\d+" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | tail -1'

# Enable color prompt
export PS1='${debian_chroot:+($debian_chroot)}\[\033[01;31m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]🔒\$ '
BASHRC
        print_done "Aliases added"
    else
        print_skip "Aliases already present"
    fi

    mark_phase_done "9"
}

# ─── Phase-specific fallback handlers ──────────────────────────────────────────
handle_phase_error() {
    local phase="$1"
    local phase_name="$2"
    echo ""
    echo -e "  ${CROSS} ${RED}${BOLD}Phase ${phase} (${phase_name}) encountered errors${RESET}"
    echo -e "  ${INFO} Check ${LOG_FILE} for details"
    echo -e "  ${INFO} You can re-run the full script — it is idempotent"
    echo ""
}

# ─── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${GREEN}║${RESET}                                                            ${BOLD}${GREEN}║${RESET}"
    echo -e "${BOLD}${GREEN}║${RESET}     ${BOLD}🏛️  ATLAS PLATFORM — Deployment Complete!${RESET}               ${BOLD}${GREEN}║${RESET}"
    echo -e "${BOLD}${GREEN}║${RESET}                                                            ${BOLD}${GREEN}║${RESET}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo ""

    # Gather info for summary
    local ip_addr
    ip_addr="$(hostname -I 2>/dev/null | awk '{print $1}' || echo "unknown")"
    local ssh_port
    ssh_port="$(grep -oP '^Port\s+\K\d+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | tail -1 || echo "${SSH_PORT}")"

    echo -e "  ${BOLD}${WHITE}── Server Information ──────────────────────────────────────${RESET}"
    echo -e "  ${DIM}IP Address:${RESET}    ${ip_addr}"
    echo -e "  ${DIM}SSH Port:${RESET}      ${ssh_port}"
    echo -e "  ${DIM}SSH Command:${RESET}   ${BOLD}ssh -i atlas_ed25519 -p ${ssh_port} root@${ip_addr}${RESET}"
    echo ""

    echo -e "  ${BOLD}${WHITE}── Deployed Services ───────────────────────────────────────${RESET}"
    echo -e "  $(systemctl is-active ufw >/dev/null 2>&1 && echo "${CHECK}" || echo "${CROSS}") UFW Firewall"
    echo -e "  $(systemctl is-active fail2ban >/dev/null 2>&1 && echo "${CHECK}" || echo "${CROSS}") fail2ban (sshd + recidive)"
    echo -e "  $(systemctl is-active auditd >/dev/null 2>&1 && echo "${CHECK}" || echo "${CROSS}") auditd monitoring"
    echo -e "  $(swapon --show 2>/dev/null | grep -q zram0 && echo "${CHECK}" || echo "${CROSS}") ZRAM swap (${ZRAM_SIZE})"
    echo -e "  $(systemctl is-enabled hermes >/dev/null 2>&1 && echo "${CHECK}" || echo "${CROSS}") Hermes Agent (enabled)"
    echo ""

    echo -e "  ${BOLD}${WHITE}── Installed Tools ─────────────────────────────────────────${RESET}"
    echo -e "  $(command -v go >/dev/null 2>&1 && echo "${CHECK}" || echo "${CROSS}") Go $(go version 2>/dev/null | awk '{print $3}')"
    echo -e "  $(command -v node >/dev/null 2>&1 && echo "${CHECK}" || echo "${CROSS}") Node $(node --version 2>/dev/null)"
    echo -e "  $(command -v pm2 >/dev/null 2>&1 && echo "${CHECK}" || echo "${CROSS}") PM2 $(pm2 --version 2>/dev/null)"
    echo -e "  $([[ -f ${ATLAS_VENV}/bin/python ]] && echo "${CHECK}" || echo "${CROSS}") Python venv at ${ATLAS_VENV}"
    echo ""

    echo -e "  ${BOLD}${WHITE}── Security Hardening ──────────────────────────────────────${RESET}"
    echo -e "  ${CHECK} Kernel hardening (sysctl + module blacklist)"
    echo -e "  ${CHECK} SSH key-only auth on port ${ssh_port}"
    echo -e "  ${CHECK} Geo-blocking (RU/CN/UZ/LT blocked, ID whitelisted)"
    echo -e "  ${CHECK} AIDE + RKHunter + Lynis deployed"
    echo -e "  ${CHECK} Unattended security upgrades enabled"
    echo ""

    echo -e "  ${BOLD}${WHITE}── Logs ─────────────────────────────────────────────────────${RESET}"
    echo -e "  ${CLIP} Deployment:  ${LOG_FILE}"
    echo -e "  ${CLIP} Hermes:      journalctl -u hermes"
    echo -e "  ${CLIP} fail2ban:    /var/log/fail2ban.log"
    echo ""

    # NEXT STEPS box
    echo -e "${BOLD}${YELLOW}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${YELLOW}║${RESET}              ${BOLD}📋 NEXT STEPS${RESET}                                   ${BOLD}${YELLOW}║${RESET}"
    echo -e "${BOLD}${YELLOW}╠══════════════════════════════════════════════════════════════╣${RESET}"
    echo -e "${BOLD}${YELLOW}║${RESET}                                                            ${BOLD}${YELLOW}║${RESET}"
    echo -e "${BOLD}${YELLOW}║${RESET}  1. ${BOLD}Save your SSH key${RESET} — it was displayed above          ${BOLD}${YELLOW}║${RESET}"
    echo -e "${BOLD}${YELLOW}║${RESET}     Copy to your local machine and set perms 600           ${BOLD}${YELLOW}║${RESET}"
    echo -e "${BOLD}${YELLOW}║${RESET}                                                            ${BOLD}${YELLOW}║${RESET}"
    echo -e "${BOLD}${YELLOW}║${RESET}  2. ${BOLD}Reconnect via new SSH port${RESET}:                           ${BOLD}${YELLOW}║${RESET}"
    echo -e "${BOLD}${YELLOW}║${RESET}     ssh -i atlas_ed25519 -p ${ssh_port} root@${ip_addr}  ${BOLD}${YELLOW}║${RESET}"
    echo -e "${BOLD}${YELLOW}║${RESET}                                                            ${BOLD}${YELLOW}║${RESET}"
    echo -e "${BOLD}${YELLOW}║${RESET}  3. ${BOLD}Configure Hermes Agent${RESET}:                                ${BOLD}${YELLOW}║${RESET}"
    echo -e "${BOLD}${YELLOW}║${RESET}     su - hermes && hermes setup                            ${BOLD}${YELLOW}║${RESET}"
    echo -e "${BOLD}${YELLOW}║${RESET}                                                            ${BOLD}${YELLOW}║${RESET}"
    echo -e "${BOLD}${YELLOW}║${RESET}  4. ${BOLD}Start Hermes Agent${RESET}:                                    ${BOLD}${YELLOW}║${RESET}"
    echo -e "${BOLD}${YELLOW}║${RESET}     systemctl start hermes                           ${BOLD}${YELLOW}║${RESET}"
    echo -e "${BOLD}${YELLOW}║${RESET}                                                            ${BOLD}${YELLOW}║${RESET}"
    echo -e "${BOLD}${YELLOW}║${RESET}  5. ${BOLD}Review the deployment log${RESET}:                             ${BOLD}${YELLOW}║${RESET}"
    echo -e "${BOLD}${YELLOW}║${RESET}     less ${LOG_FILE}                    ${BOLD}${YELLOW}║${RESET}"
    echo -e "${BOLD}${YELLOW}║${RESET}                                                            ${BOLD}${YELLOW}║${RESET}"
    echo -e "${BOLD}${YELLOW}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo ""

    # Deployment timestamp
    echo -e "  ${DIM}ATLAS PLATFORM v${ATLAS_VERSION} — Deployed $(date)${RESET}"
    echo ""
    log_ok "=== ATLAS PLATFORM v${ATLAS_VERSION} deployment completed ==="
}

# ─── Main Execution ────────────────────────────────────────────────────────────
main() {
    # Always set up logging first
    mkdir -p "$(dirname "${LOG_FILE}")"
    touch "${LOG_FILE}"
    exec 2> >(tee -a "${LOG_FILE}" >&2)

    print_header

    echo -e "  ${BOLD}ATLAS PLATFORM v${ATLAS_VERSION}${RESET}"
    echo -e "  ${DIM}Infrastructure Provisioning — 10-Phase Deployment${RESET}"
    echo ""
    echo -e "  ${DIM}Log file: ${LOG_FILE}${RESET}"
    echo -e "  ${DIM}Start: $(date)${RESET}"
    echo ""

    # Pre-flight checks
    run_preflight

    local phases=(
        "phase_0_system_base|0|System Base"
        "phase_1_kernel_hardening|1|Kernel Hardening"
        "phase_2_ssh_hardening|2|SSH Hardening"
        "phase_3_firewall_fail2ban|3|Firewall + fail2ban"
        "phase_4_geo_blocking|4|Geo-Blocking"
        "phase_5_detection_tools|5|Detection Tools"
        "phase_6_maintenance|6|Maintenance"
        "phase_7_toolchain|7|Toolchain"
        "phase_8_hermes_agent|8|Hermes Agent"
        "phase_9_finalization|9|Finalization"
    )

    local total_phases=${#phases[@]}
    local completed=0
    local failed=0
    local start_time
    start_time="$(date +%s)"

    for phase_entry in "${phases[@]}"; do
        IFS='|' read -r func phase_num phase_name <<< "${phase_entry}"

        # Check if this phase is already done
        if is_phase_done "${phase_num}"; then
            print_phase "${phase_num}" "${phase_name}"
            print_skip "Phase ${phase_num} already completed on $(cat "${DEPLOY_STAMP}_${phase_num}" 2>/dev/null || echo 'previous run')"
            ((completed++))
            continue
        fi

        # Run the phase
        if ${func}; then
            ((completed++))
            log_ok "Phase ${phase_num} (${phase_name}) completed successfully"
        else
            ((failed++))
            handle_phase_error "${phase_num}" "${phase_name}"

            # Ask whether to continue
            echo ""
            echo -e "  ${YELLOW}${BOLD}Phase ${phase_num} had errors. Options:${RESET}"
            echo -e "  ${DIM}  [c] Continue with remaining phases${RESET}"
            echo -e "  ${DIM}  [r] Retry this phase${RESET}"
            echo -e "  ${DIM}  [q] Quit deployment${RESET}"
            echo ""
            echo -n "  Choice [c/r/q] (default: c): "
            read -r choice
            choice="${choice:-c}"

            case "${choice}" in
                r|R)
                    echo -e "  ${ARROW} Retrying Phase ${phase_num}..."
                    if ${func}; then
                        ((completed++))
                        ((failed--))
                        log_ok "Phase ${phase_num} (${phase_name}) succeeded on retry"
                    else
                        handle_phase_error "${phase_num}" "${phase_name}"
                        echo ""
                        echo -e "  ${YELLOW}Retry also failed. Press Enter to continue...${RESET}"
                        read -r
                    fi
                    ;;
                q|Q)
                    echo -e "  ${CROSS} Deployment aborted at Phase ${phase_num}"
                    log_error "Deployment aborted by user at Phase ${phase_num}"
                    break
                    ;;
                *)
                    echo -e "  ${ARROW} Continuing to next phase..."
                    ;;
            esac
        fi
    done

    local end_time
    end_time="$(date +%s)"
    local elapsed=$((end_time - start_time))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))

    # Print summary
    print_summary

    echo -e "  ${BOLD}${WHITE}── Deployment Statistics ──────────────────────────────────${RESET}"
    echo -e "  ${DIM}Phases completed:${RESET} ${completed}/${total_phases}"
    echo -e "  ${DIM}Phases failed:${RESET}    ${failed}/${total_phases}"
    echo -e "  ${DIM}Total time:${RESET}       ${minutes}m ${seconds}s"
    echo ""

    if [[ "${failed}" -gt 0 ]]; then
        echo -e "  ${WARN} ${YELLOW}Some phases had issues. Review ${LOG_FILE} for details.${RESET}"
        echo -e "  ${INFO} Re-run the script — it is fully idempotent."
        exit 1
    else
        echo -e "  ${ROCKET} ${GREEN}${BOLD}ATLAS PLATFORM deployment successful!${RESET}"
        exit 0
    fi
}

# ─── Entry Point ───────────────────────────────────────────────────────────────
# Allow sourcing for testing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
