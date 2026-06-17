# ⚠️ Perhatian Penting: VPS vs Codespace

Repo ini (`atlas-platform`) dirancang untuk **provisioning VPS Ubuntu 24.04** dan menjalankan Docker infrastructure stack. Ada repo pendamping [`talos-engine`](https://github.com/leonidastcejorp/talos-engine) yang berisi automation framework untuk airdrop farming dan bug bounty recon.

## 📑 Dua Repository, Dua Fungsi

| Repo | Target | Isi Utama | Cara Pakai |
|------|--------|-----------|------------|
| **`atlas-platform`** | VPS (production) | `setup.sh`, hardening, Docker stack, systemd service | Clone ke `/opt/atlas-platform`, jalankan `bash setup.sh` |
| **`talos-engine`** | VPS + Codespace | Modul Python `farm/`, `bounty/`, `flowcore/`, tools | Clone ke `/opt/atlas/projects/talos-engine`, install deps |

## 🛡️ Catatan Keamanan

1. **Jangan commit secrets ke repo**
   - Wallet file: `~/.talos/wallets.json`
   - Hermes auth: `~/.hermes/auth.json`
   - Environment file: `.env` (sudah di-ignore)
   - SSH private key: `~/.ssh/atlas_ed25519`

2. **Gunakan `.env.example` sebagai template**
   ```bash
   cp .env.example .env
   # isi dengan nilai asli, jangan di-commit
   ```

## 🔄 Migrasi ke VPS Baru

Git clone **tidak cukup** buat membuat sistem berjalan persis sama. Berikut yang harus diperhatikan:

| Yang di-clone | Yang harus di-migrate manual |
|---------------|------------------------------|
| `atlas-platform` + `talos-engine` | Wallet, auth, `.env`, proxy pool |
| Docker stack di `stacks/infra/` | Data container/volume di `/var/lib/docker/` |
| Systemd service dari `setup.sh` | State cron & log di `~/.hermes/` |
| Konfigurasi hardening | SSH key + authorized_keys |

### Langkah migrasi yang disarankan

```bash
# 1. Provision VPS baru dari repo ini
git clone https://github.com/leonidastcejorp/atlas-platform.git /opt/atlas-platform
cd /opt/atlas-platform && bash setup.sh

# 2. Clone talos-engine
git clone https://github.com/leonidastcejorp/talos-engine.git /opt/atlas/projects/talos-engine
cd /opt/atlas/projects/talos-engine && pip install -r requirements.txt

# 3. Restore secrets & state dari backup lama
#    - ~/.talos/wallets.json
#    - ~/.hermes/auth.json
#    - ~/projects/bounty-output/proxies/
#    - file .env

# 4. Deploy infrastructure stack (opsional)
cd /opt/atlas-platform/stacks/infra
cp .env.example .env
# edit .env
bash deploy.sh

# 5. Setup ulang Hermes model/provider
su - hermes
hermes setup
hermes setup tools
```

## 💾 Path Penting di VPS

| Path | Keterangan |
|------|------------|
| `/opt/atlas/` | Home direktori utama aplikasi |
| `/opt/atlas/projects/` | Clone repo `talos-engine` dan project lain |
| `/opt/atlas-platform/` | Clone repo `atlas-platform` (ini) |
| `/home/hermes/.hermes/` | Config & state Hermes Agent |
| `/etc/systemd/system/hermes.service` | Service Hermes Agent |

## ⚠️ Yang Bisa Bentrok

- **Path `/root/projects/` vs `/opt/atlas/projects/`**: Di VPS lama project ada di `/root/projects/`, tapi `setup.sh` menggunakan `/opt/atlas/projects/`. Pilih salah satu dan konsisten.
- **Hermes service**: `setup.sh` sekarang membuat `/etc/systemd/system/hermes.service` dengan `ExecStart=hermes gateway run`. Kalau masih ada service lama `hermes-agent.service`, hapus dulu.
- **Port SSH**: Default `setup.sh` mengubah SSH ke port `2222` dan key-only. Pastikan punya akses console VPS sebelum deploy.
- **UFW & Docker**: Docker bisa bypass UFW. Jangan expose port container ke publik kecuali sudah melalui Traefik dengan TLS.

## 📋 Catatan Codespace

- Codespace cocok untuk development & test `talos-engine`, **bukan** untuk menjalankan `setup.sh`.
- Di codespace tidak perlu menjalankan hardening atau systemd.
- Cukup clone `talos-engine`, install deps, dan jalankan unit test.

## 📞 Support

Kalau ada yang rusak setelah migrasi, cek log:
```bash
journalctl -u hermes -n 100 --no-pager
tail -100 /var/log/atlas-deploy.log
```
