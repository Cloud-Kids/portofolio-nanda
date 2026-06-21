# 🚀 Panduan Deployment Otomatis — Static Website ke Proxmox LXC (GitOps Pipeline)

Repo ini adalah pipeline CI/CD lengkap yang menggabungkan **Terraform** (Infrastructure as Code) dan **GitHub Actions** (rsync deployment) untuk men-deploy website statis ke dua LXC container Active-Active di Proxmox — tanpa intervensi manual setelah setup awal selesai.

---

## 🏗️ Arsitektur

```
                     ┌──────────────────────┐
                     │   Cloudflare Edge    │
                     │  (Auto Load Balance  │
                     │   & Failover)        │
                     └──────────┬───────────┘
                                │
         ┌──────────────────────┴──────────────────────┐
         │ (Tunnel Conn 1)                             │ (Tunnel Conn 2)
         ▼                                             ▼
┌──────────────────┐                          ┌──────────────────┐
│     CT web1      │                          │     CT web2      │
│   10.10.10.111   │                          │   10.10.10.112   │
│   (node1)        │                          │   (node2)        │
│  [cloudflared]   │                          │  [cloudflared]   │
│  [nginx → :80]   │                          │  [nginx → :80]   │
└──────────────────┘                          └──────────────────┘
         ▲                                             ▲
         │              ┌──────────────┐               │
         └──────────────│ Self-Hosted  │───────────────┘
                        │   Runner     │
                        │ 10.10.10.110 │
                        └──────┬───────┘
                               │
                        ┌──────┴───────┐
                        │    GitHub    │
                        │  Repository  │
                        └──────────────┘
```

**Alur kerja setelah setup selesai:**
1. `git push` ke branch `main`
2. GitHub Actions trigger self-hosted runner
3. **Job 1 (Terraform):** Buat CT + inject `cloudflared` dengan token tunnel (auto-HA!)
4. **Job 2 (Rsync):** Deploy file website ke kedua CT secara paralel
5. Cloudflare Edge deteksi 2 tunnel connections → auto load balance + failover!

---

## 🔄 Pipeline Flow (CI/CD + End-to-End Self-Healing)

Pipeline ini memiliki **3 tahap** (CI → CD Provision → CD Deploy) dengan **3 layer self-healing** yang otomatis memperbaiki masalah jaringan dan permission tanpa intervensi manual:

```
┌──────────────────── TAHAP 0: CI Gatekeeper ────────────────────────────────┐
│                                                                            │
│  📥 Checkout → 🔬 HTML validation → 🛡️ Secret scan                        │
│             → 📦 Asset check     → 🏗️ Terraform fmt                       │
│                                                                            │
│  Kalau GAGAL → pipeline STOP. Terraform & rsync TIDAK jalan.               │
│  Server produksi tetap aman menampilkan versi terakhir yang normal.         │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────── TAHAP 1: Terraform Provisioning ────────────────────┐
│                                                                         │
│  CT boot → flush network → static IP + DNS → diagnostic snapshot        │
│       │                                                                 │
│       ▼                                                                 │
│  ┌─ Self-Healing: apk update (150s) ───────────────────────┐            │
│  │  attempts 1-7:   retry apk update (TCP connectivity)    │            │
│  │  attempt 8  (25%): 🔧 re-apply DNS + restart networking │            │
│  │  attempts 9-14:  retry                                  │            │
│  │  attempt 15 (50%): 🔧 re-apply DNS + restart networking │            │
│  │  attempts 16-22: retry                                  │            │
│  │  attempt 23 (75%): 🔧 re-apply DNS + restart networking │            │
│  │  attempts 24-30: final retry → exit 99 if still failing │            │
│  └─────────────────────────────────────────────────────────┘            │
│       │                                                                 │
│       ▼                                                                 │
│  OpenRC init → apk add openssh/curl/rsync/nginx → SSH config            │
│  → mkdir /var/www/html (chmod 777) → cloudflared tunnel service         │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌──────────────────── TAHAP 2: Deploy (GitHub Actions) ───────────────────┐
│                                                                         │
│  SSH key setup + known_hosts (CT + Proxmox hosts)                       │
│       │                                                                 │
│       ▼                                                                 │
│  ┌─ Self-Healing: SSH Readiness (150s) ───────────────────┐             │
│  │  attempt N: ssh "echo ok" → success? done              │             │
│  │  at 25%/50%/75%:                                       │             │
│  │    🔧 lxc-attach restart sshd (via Proxmox host)       │             │
│  │    🔧 re-apply DNS (/etc/resolv.conf)                  │             │
│  │    🔧 verify network interface (ip addr show)          │             │
│  └────────────────────────────────────────────────────────┘             │
│       │                                                                 │
│       ▼                                                                 │
│  ┌─ Self-Healing: Rsync Parallel (150s) ──────────────────┐             │
│  │  attempt N: rsync → exit 0? done                        │            │
│  │  flags: --no-perms --no-owner --no-group (Alpine-safe)  │            │
│  │  at 25%/50%/75%:                                        │            │
│  │    🔧 chmod 777 /var/www/html (via lxc-attach)          │            │
│  │    🔧 restart sshd                                      │            │
│  │    🔧 re-apply DNS                                      │            │
│  └─────────────────────────────────────────────────────────┘             │
│       │                                                                  │
│       ▼                                                                  │
│  Fix permissions (chmod 755/644) → cleanup SSH key                      │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```



---

## 📋 Prasyarat (Prerequisites)

Minimal yang harus sudah ada sebelum memulai:

- ✅ **Proxmox VE** terinstall dengan minimal 1 node (idealnya 2: `node1` & `node2`)
- ✅ **Akun GitHub** dengan repository yang berisi kode website
- ✅ **Koneksi internet** di node Proxmox (untuk download template & GitHub runner)
- ✅ **Proxmox API Token** sudah dibuat (dijelaskan di Step 3)

> 💡 **Catatan:** CT web target (web1 & web2) TIDAK perlu dibuat manual — Terraform akan membuatnya otomatis di Step 4!

---

## 🏃 Step 1: Siapkan Mesin Runner (Jembatan Utama)

> ⚠️ **TANPA RUNNER, SELURUH PIPELINE INI TIDAK AKAN JALAN.**
>
> Self-hosted runner adalah "jembatan" antara GitHub Cloud dan jaringan lokal Proxmox. GitHub tidak bisa langsung menembak IP private 10.10.10.x — runner lah yang menerima instruksi dari GitHub lalu mengeksekusinya di jaringan lokal.

### 1.0 — Lokasi Runner: CT Dedicated (Opsi A)

> 💡 **Asas Kemalasan Hakiki:** Daripada buat CT Runner manual lewat GUI, kamu juga bisa definisikan mesin `github-runner` ini di file `main.tf` Terraform sekalian! Tapi untuk bootstrap awal, kita perlu minimal 1 runner manual dulu agar Terraform bisa dijalankan.

**Buat CT via Proxmox GUI:**

| Parameter | Value |
|-----------|-------|
| CT ID | 110 |
| Hostname | `github-runner` |
| Template | **Debian 13** atau **Ubuntu 24.04** |
| CPU | 1 cores |
| RAM | 128 MB |
| SWAP | 128 MB |
| Disk | 3 GB |
| Network | Bridge `vmbr0`, IP: `10.10.10.110/24`, GW: `10.10.10.1` |

> ⚠️ **JANGAN pakai Alpine Linux untuk runner!** GitHub Actions Runner butuh **glibc**. Alpine pakai **musl libc** yang tidak kompatibel — binary runner akan crash saat startup.

### 1.1 — Persiapan Mesin Runner

Setelah CT `github-runner` dibuat dan jalan, SSH ke dalamnya:

```bash
ssh root@10.10.10.110
```

Install semua dependensi:

```bash
# Update system
apt update && apt upgrade -y

# Install dependensi yang dibutuhkan runner + workflow
apt install -y sudo curl tar git rsync openssh-client unzip nodejs
```

Buat user khusus (JANGAN jalankan runner sebagai root!):

```bash
# Buat user runner
useradd -m -s /bin/bash runner

# Tambahkan ke grup sudo
usermod -aG sudo runner

# Agar runner bisa jalankan sudo tanpa password di workflow otomatis
echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Pindah ke user runner
su - runner
```

### 1.2 — Download & Install GitHub Actions Runner

**Ambil registration token dari GitHub:**
1. Ke repository → **Settings** → **Actions** → **Runners**
2. Klik **New self-hosted runner**
3. Pilih **Linux** → **x64**
4. Copy token yang muncul

**Install runner (jalankan sebagai user `runner`):**

```bash
# Buat direktori dan download
mkdir ~/actions-runner && cd ~/actions-runner
curl -o actions-runner-linux-x64-2.321.0.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.321.0/actions-runner-linux-x64-2.321.0.tar.gz
tar xzf ./actions-runner-linux-x64-2.321.0.tar.gz

# Konfigurasi — ganti NAMA-REPO sesuai milikmu
./config.sh --url https://github.com/Org-Name/NAMA-REPO --token TOKEN_DARI_GITHUB
```

Saat ditanya interaktif:
```
Enter the name of the runner group: [tekan Enter untuk default]
Enter the name of runner: [tekan Enter atau ketik "proxmox-runner"]
Enter any additional labels: [tekan Enter]
Enter the name of work folder: [tekan Enter untuk default "_work"]
```

### 1.3 — Install Sebagai Service (Auto-Start)

> ⚠️ **JANGAN jalankan `./run.sh`!** GitHub mungkin menampilkan perintah ini di halaman runner:
> ```
> # Last step, run it!
> $ ./run.sh
> ```
> Ini hanya untuk test interaktif — **runner tidak akan jalan otomatis saat CT restart.** Langsung lanjut ke install service di bawah.

```bash
# Kembali ke root untuk install service
exit  # kembali ke root

cd /home/runner/actions-runner
sudo ./svc.sh install runner
sudo ./svc.sh start
```

Verifikasi:
```bash
sudo ./svc.sh status
```

Cek di GitHub: **Settings → Actions → Runners** — runner harus berstatus **🟢 Idle**.

### 1.4 — Verifikasi Konektivitas Jaringan Runner

Sebelum lanjut, pastikan CT runner sudah bisa "melihat" jaringan lokal Proxmox (minimal bisa ping gateway atau host Proxmox):

```bash
# Test ping ke Gateway
ping -c 3 10.10.10.1

# Test ping ke IP Host Proxmox (node1)
ping -c 3 10.10.10.201
```

> 💡 **Catatan untuk Jalur Terraform (Opsi A):** Kamu **BELUM** bisa ping ke `10.10.10.111` atau `10.10.10.112` sekarang — kontainernya memang belum dibuat! Yang penting di tahap ini: pastikan runner sudah tersambung ke jaringan lokal dan bisa mengakses internet (untuk download GitHub runner package).
>
> Setelah Step 5 (git push) berhasil dan Terraform membuat kedua CT, barulah kamu bisa verifikasi koneksi penuh:
> ```bash
> ping -c 3 10.10.10.111   # web1
> ping -c 3 10.10.10.112   # web2
> ```

### 1.5 — Cabut Runner (Jika Perlu Ganti Token / Pindah Repo)

> ⚠️ **Jangan langsung `config.sh remove`!** Kalau runner masih terinstall sebagai systemd service, kamu harus uninstall service DULU. Urutan yang salah bikin runner "nyangkut" (ghost runner) di GitHub.

**Urutan yang benar:**

```bash
cd /home/runner/actions-runner

# 1. Stop service
sudo ./svc.sh stop

# 2. Uninstall systemd service
sudo ./svc.sh uninstall

# 3. Baru cabut runner dari GitHub (butuh remove token baru dari GitHub UI)
./config.sh remove --token <REMOVE_TOKEN>
```

**Dapatkan Remove Token dari GitHub:**
1. Buka repo → **Settings → Actions → Runners**
2. Klik runner yang mau dicabut
3. Klik **Remove** → copy token yang muncul

**Output sukses:**
```
√ Runner removed successfully
√ Removed .credentials
√ Removed .runner
```

> 💡 **Kapan perlu cabut runner?**
> - Ganti repository (repo lama dihapus/di-rename)
> - Runner error parah dan perlu re-register dari nol
> - Pindah runner ke CT/mesin lain
>
> Setelah cabut, jalankan ulang `./config.sh --url ... --token ...` seperti Step 1.3 untuk register baru.

---

## 🔑 Step 2: Generate SSH Key Pair (di Mesin Runner)

SSH key ini dipakai untuk autentikasi tanpa password antara runner → kedua CT web. Algoritma **ed25519** lebih aman dan key-nya lebih pendek dari RSA.

### Jalankan sebagai user `runner` di CT github-runner:

```bash
su - runner
ssh-keygen -t ed25519 -C "github-deploy-key" -f ~/.ssh/id_ed25519
```

### Contoh output:

```
Generating public/private ed25519 key pair.
Enter passphrase (empty for no passphrase):   ← Tekan Enter (kosongkan!)
Enter same passphrase again:                   ← Tekan Enter lagi
Your identification has been saved in /home/runner/.ssh/id_ed25519
Your public key has been saved in /home/runner/.ssh/id_ed25519.pub
The key fingerprint is:
SHA256:AbCdEfGhIjKlMnOpQrStUvWxYz1234567890 github-deploy-key
```

### Hasil: 2 file tercipta

| File | Isinya | Kemana perginya? |
|------|--------|-----------------|
| `~/.ssh/id_ed25519` | **Private Key** 🔒 | → GitHub Secret `DEPLOY_KEY` |
| `~/.ssh/id_ed25519.pub` | **Public Key** 🔑 | → GitHub Secret `DEPLOY_PUBLIC_KEY` + ditanam di CT target |

### ⚠️ PERINGATAN — Private Key = Kunci Rumah!

- ❌ JANGAN commit ke repository
- ❌ JANGAN kirim lewat chat/email
- ❌ JANGAN paste di tempat publik
- ✅ HANYA simpan di GitHub Secrets (terenkripsi)

---

## 🔐 Step 3: Pasang Semua Secrets di GitHub (Satu Kali, Tuntas!)

> 💡 **Kita selesaikan SEMUA konfigurasi GitHub Secrets di sini, supaya tidak bolak-balik.**

### 3.1 — Buka halaman Secrets:

1. Ke repository di GitHub
2. **Settings** → **Secrets and variables** → **Actions**
3. Klik **New repository secret**

### 3.2 — Daftar SEMUA Secrets yang Dibutuhkan:

| # | Secret Name | Cara Mendapatkan Value-nya | Contoh Value |
|---|---|---|---|
| 1 | `DEPLOY_USER` | Username SSH ke CT target | `root` |
| 2 | `DEPLOY_KEY` | `cat ~/.ssh/id_ed25519` (dari Step 2) | `-----BEGIN OPENSSH PRIVATE KEY-----` ... `-----END OPENSSH PRIVATE KEY-----` |
| 3 | `DEPLOY_PUBLIC_KEY` | `cat ~/.ssh/id_ed25519.pub` (dari Step 2) | `ssh-ed25519 AAAAC3Nz... github-deploy-key` |
| 4 | `PVE_API_TOKEN` | Dari Proxmox Web UI (lihat di bawah) | `root@pam!terraform=a1b2c3d4-e5f6-...` |
| 5 | `CF_TUNNEL_TOKEN` | Cloudflare Zero Trust Dashboard → Tunnels → Create → copy token | `eyJhIjoiNjk2MT...` (token panjang) |

### 3.3 — Cara Buat Proxmox API Token (`PVE_API_TOKEN`):

1. Login ke **Proxmox Web UI** (https://10.10.10.201:8006)
2. **Datacenter** → **Permissions** → **API Tokens**
3. Klik **Add**
4. User: `root@pam`, Token ID: `terraform`
5. **UNCHECK** "Privilege Separation"
6. Klik **Add** → **COPY token yang muncul SEGERA** (hanya muncul sekali!)

```
Format yang muncul:
root@pam!terraform=a1b2c3d4-e5f6-7890-abcd-ef1234567890
└─────────────────┘ └──────────────────────────────────┘
   Token ID              Token Secret (HANYA MUNCUL SEKALI!)
```

> ⚠️ **PENTING:** Copy **SELURUH string lengkap** termasuk `root@pam!terraform=` di depannya!
> Yang dimasukkan ke Secret itu **BUKAN** cuma UUID-nya (`a1b2c3d4-...`), tapi **LENGKAP** dari awal sampai akhir!

### 3.3.1 — Cara Buat Cloudflare Tunnel Token (`CF_TUNNEL_TOKEN`):

1. Login ke **Cloudflare Zero Trust Dashboard** (https://one.cloudflare.com)
2. Ke **Networks** → **Tunnels**
3. Klik **Create a tunnel**
4. Pilih **Cloudflared** → klik **Next**
5. Beri nama tunnel (contoh: `web-ha`) → klik **Save tunnel**
6. Di halaman berikutnya, pilih environment **Debian** / **64-bit**
7. **COPY token yang muncul** — ini adalah `CF_TUNNEL_TOKEN` kamu!

```
Format token:
eyJhIjoiNjk2MT...(string panjang base64)...
```

> ⚠️ Token ini hanya muncul **sekali saat pembuatan**. Simpan segera ke GitHub Secret `CF_TUNNEL_TOKEN`!
> Token sudah embed tunnel ID + credentials di dalamnya — cloudflared akan langsung terhubung ke tunnel yang kamu buat.

### 3.4 — Cara Paste `DEPLOY_KEY` (Private Key):

```bash
# Di mesin runner:
cat ~/.ssh/id_ed25519
```

Output:
```
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACBHp1mVRv7lBn3JmI6Q0fTqoQAAAED1Y2F1bS1yc2Etc2lnbmF0dXJl...
-----END OPENSSH PRIVATE KEY-----
```

> Copy **SELURUH isi** dari `-----BEGIN...` sampai `-----END...-----` (termasuk baris BEGIN dan END). Jangan sampai kepotong!

### 3.5 — Cara Paste `DEPLOY_PUBLIC_KEY`:

```bash
cat ~/.ssh/id_ed25519.pub
```

Output (satu baris):
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAbCdEfGhIjKlMnOpQrStUvWxYz github-deploy-key
```

> Copy **seluruh baris** itu. Terraform akan menanamnya otomatis ke CT baru saat provisioning — jadi CT langsung bisa di-SSH tanpa setup manual!

### ✅ Checklist Secrets (Pastikan 5/5 terisi!):

```
☐ DEPLOY_USER       → root
☐ DEPLOY_KEY        → (isi private key lengkap)
☐ DEPLOY_PUBLIC_KEY → (isi public key satu baris)
☐ PVE_API_TOKEN     → root@pam!terraform=xxxxx...
☐ CF_TUNNEL_TOKEN   → (token dari Cloudflare Dashboard)
```

### 🔐 Step 3.6: Tanam Public Key ke Proxmox Host (WAJIB!)

> ⚠️ **INI SERING TERLEWAT!** Terraform perlu SSH ke **Proxmox host** (node1 & node2) untuk menjalankan `lxc-attach`. Tanpa key ini, pipeline GAGAL dengan error `SSH authentication failed`.

SSH ke **setiap Proxmox node** (via Proxmox Web Console atau fisik), lalu jalankan:

**Node 1 (10.10.10.201):**
```bash
# Pastikan directory ada
mkdir -p /root/.ssh && chmod 700 /root/.ssh

# Paste public key yang SAMA dengan DEPLOY_PUBLIC_KEY di GitHub Secrets
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK/HVq... github-deploy-key" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
```

**Node 2 (10.10.10.202):**
```bash
mkdir -p /root/.ssh && chmod 700 /root/.ssh
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK/HVq... github-deploy-key" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
```

> 💡 **Kenapa perlu?** Terraform tidak bisa pakai API Proxmox untuk provisioning LXC (Alpine SSH belum aktif). Jadi Terraform SSH ke host dulu → `lxc-attach` ke dalam CT → setup networking + SSH dari dalam.

**Verifikasi known_hosts di runner (WAJIB!):**

> ⚠️ **INI PENYEBAB UTAMA GAGAL!** Kalau runner belum pernah SSH ke suatu host, fingerprint host belum ada di `known_hosts`. Terraform **tidak bisa** jawab prompt interaktif “Are you sure?” — hasilnya langsung GAGAL.

```bash
# Di runner, tambahkan semua host key ke known_hosts:
ssh-keyscan -H 10.10.10.201 >> ~/.ssh/known_hosts 2>/dev/null
ssh-keyscan -H 10.10.10.202 >> ~/.ssh/known_hosts 2>/dev/null
ssh-keyscan -H 10.10.10.111 >> ~/.ssh/known_hosts 2>/dev/null
ssh-keyscan -H 10.10.10.112 >> ~/.ssh/known_hosts 2>/dev/null
```

> 💡 Workflow sudah include step `ssh-keyscan` otomatis di **provision job** dan **deploy job**. Tapi untuk first-time setup, jalankan manual dulu!

**Verifikasi key fingerprint match (DEPLOY_KEY Secret ↔ runner):**
```bash
# Di runner, cek fingerprint key lokal:
ssh-keygen -lf ~/.ssh/id_ed25519
# Output: 256 SHA256:xxxxx... github-deploy-key (ED25519)

# Fingerprint ini HARUS SAMA dengan public key di authorized_keys Proxmox host!
```

**Verifikasi dari runner:**
```bash
# Di runner (10.10.10.110), test SSH ke kedua Proxmox host:
ssh -i ~/.ssh/id_ed25519 root@10.10.10.201 "echo node1 OK"
ssh -i ~/.ssh/id_ed25519 root@10.10.10.202 "echo node2 OK"
```

Kalau langsung masuk tanpa password → **aman!** 🎉

> 🧹 **Tips:** Cek `authorized_keys` untuk entry duplikat atau placeholder `YOUR_DEPLOY_PUBLIC_KEY` yang belum diganti — hapus yang tidak perlu!

---

## 🏗️ Step 4: Provisioning Infrastruktur dengan Terraform

Sebelum file website bisa di-deploy, kita butuh dua LXC Container (`web1` & `web2`) sebagai server target.

> **Kamu tidak perlu buka GUI Proxmox. Kamu tidak perlu SSH manual. Kamu tidak perlu `nano` apapun.**

Cukup pastikan file `terraform/variables.tf` sudah sesuai spesifikasi keinginanmu. Saat kamu melakukan `git push` di Step 5 nanti, GitHub Actions akan menyuruh Terraform untuk:

1. ✅ Membuat CT `web1` di node1 (IP: 10.10.10.111)
2. ✅ Membuat CT `web2` di node2 (IP: 10.10.10.112)
3. ✅ Menanam `DEPLOY_PUBLIC_KEY` secara otomatis ke kedua CT
4. ✅ Set CPU, RAM, disk sesuai `variables.tf`
5. ✅ Start kedua CT
6. ✅ **Self-healing network setup: flush → static IP → DNS → connectivity check**
7. ✅ **Install OpenSSH + configure sshd + Cloudflared tunnel via `lxc-attach`**
8. ✅ **Install + configure nginx (serve `/var/www/html` di port 80)**
9. ✅ **Buat `/var/www/html` (chmod 777) untuk rsync target**

**Kamu langsung skip ke Step 5. Tidak ada kerja manual!** 🎉

#### 📁 Struktur Direktori Terraform:

```
terraform/
├── main.tf                      ← Provider + resource CT web1 & web2 (lxc-attach provisioning)
├── variables.tf                 ← Spesifikasi (CPU, RAM, disk, IP, node host, template)
├── outputs.tf                   ← Output IP & hostname setelah apply
├── download-template.tf.example ← (Opsional) Rename ke .tf jika mau auto-download template
└── .gitignore                   ← Exclude .terraform/, *.tfstate
```

> **🔧 Host-Based Provisioning (lxc-attach)**
> Alpine Linux di Proxmox **tidak menyalakan SSH secara default**. Daripada pakai hook script (yang butuh `root@pam` dan snippets), kita pakai strategi yang lebih robust:
>
> 1. Terraform SSH ke **Proxmox host** (10.10.10.201 / .202)
> 2. Dari host, jalankan `lxc-attach -n <VMID>` untuk:
>    - Setup network (flush → static IP → DNS `/etc/resolv.conf`)
>    - Self-healing `apk update` loop (150s, repair at 25%/50%/75%)
>    - Enable SSH (`PermitRootLogin`, `PubkeyAuthentication`, start sshd)
>    - Install Cloudflare Tunnel + buat OpenRC init script
>    - Install + configure nginx (root `/var/www/html`, port 80)
>    - Buat `/var/www/html` dengan `chmod 777`
> 3. CT sekarang siap menerima rsync di Tahap 2!
>
> **Keuntungan:** Bypass 403 hookscript, bypass "no route to host", self-healing network, dan tidak perlu snippets storage!

#### ⚙️ Kustomisasi Spesifikasi CT:

Edit `terraform/variables.tf`:

```hcl
variable "ct_cpu_cores" {
  default = 1      # Ubah sesuai keinginan
}

variable "ct_memory" {
  default = 128   # Dalam MB
}

variable "ct_swap" {
  default = 128   # Dalam MB
}

variable "ct_disk_size" {
  default = 1     # Dalam GB
}

variable "ct_os_template" {
  default = "local:vztmpl/alpine_3.23_amd64_default.tar.xz"
}

# IP management Proxmox node (untuk SSH + lxc-attach)
variable "proxmox_node1_host" {
  default = "10.10.10.201"  # Sesuaikan dengan IP node1 kamu
}

variable "proxmox_node2_host" {
  default = "10.10.10.202"  # Sesuaikan dengan IP node2 kamu
}
```

#### ♻️ Idempotensi — Aman Push Berkali-kali!

- Push pertama: Terraform buat CT dari nol
- Push kedua, ketiga, dst: Terraform cek → "udah sesuai" → **skip**
- CT hanya di-recreate jika kamu ubah konfigurasi di `main.tf`



## 🚀 Step 5: Push Kode & Deploy Otomatis!

Semua setup sudah selesai. Sekarang tinggal push!

### 5.1 — Push ke main:

```bash
git add .
git commit -m "🚀 first automated deploy"
git push origin main
```

### 5.2 — Apa yang terjadi di belakang layar:

```
Push ke main
    │
    ▼
┌─────────────────────────────────────┐
│  🏗️ Job 1: provision                │
│  Terraform Init + Apply             │  ← Buat/pastikan CT ada (idempoten)
│  working-dir: terraform/            │     + self-healing network + SSH + cloudflared
└──────────────┬──────────────────────┘
               │ (lanjut jika sukses)
               ▼
┌──────────────────────────────────────────┐
│  🚀 Job 2: deploy                        │
│  Step 1: Checkout + SSH key setup        │
│  Step 2: known_hosts (CT + PVE)          │
│  Step 3: SSH readiness (self-heal)       │  ← Retry + lxc-attach repair sshd
│  Step 4: Rsync parallel (self-heal)      │  ← Retry + fix perms via Proxmox
│  Step 5: Fix permissions + reload nginx  │
│  Step 6: Cleanup SSH key                 │
└──────────────────────────────────────────┘
```

### 5.3 — Monitor di GitHub:

1. Ke tab **Actions** di repository
2. Klik workflow run yang muncul
3. Log sukses kira-kira gini:

```
=========================================
🔄 Mulai deploy paralel ke kedua CT...
   → CT web1: 10.10.10.111
   → CT web2: 10.10.10.112
=========================================
⏳ Menunggu kedua rsync selesai...
  [10.10.10.111] attempt 1/30: ✅ rsync SUCCESS
  [10.10.10.112] attempt 1/30: ✅ rsync SUCCESS

=== 📋 Log rsync CT web1 (10.10.10.111) ===
...
=== 📋 Log rsync CT web2 (10.10.10.112) ===
...

✅ Sukses deploy ke CT web1
✅ Sukses deploy ke CT web2
🎉 Kedua deploy sukses!
```

### 5.4 — Verifikasi:

Buka browser → akses website. Refresh beberapa kali untuk memastikan kedua CT serve konten yang sama (Cloudflare auto load balance melalui tunnel).

---

## ☁️ Cloudflare Tunnel: Setup di Dashboard

Setelah pipeline berhasil jalan dan kedua CT memiliki `cloudflared` yang aktif, konfigurasi di sisi Cloudflare:

### Di Cloudflare Zero Trust Dashboard:

1. Ke **Networks** → **Tunnels**
2. Kamu akan melihat tunnel kamu dengan status **2 Connections** (healthy) ✅
3. Klik tunnel → **Public Hostname** → **Add**
4. Konfigurasi:
   - **Subdomain:** `www` (atau sesuai domain kamu)
   - **Domain:** `domainmu.com`
   - **Type:** `HTTP`
   - **URL:** `localhost:80`

> 💡 Karena `cloudflared` jalan **di dalam** masing-masing CT, `localhost:80` merujuk ke Nginx internal CT itu sendiri. Tidak perlu IP private!

### Hasil di Dashboard:

```
Tunnel: "web-ha"
Status: ✅ Healthy
Connections: 2 (10.10.10.111, 10.10.10.112)
```

Jika salah satu CT mati → Cloudflare otomatis failover ke CT yang masih hidup dalam hitungan milidetik. **Zero local SPOF!**

---

## 📁 Struktur Project Lengkap

```
CYSEC-V2/
│
├── .github/workflows/
│   └── deploy.yml                  ← GitHub Actions workflow (2-job pipeline)
│
├── terraform/
│   ├── main.tf                     ← Provider + resource CT web1 & web2
│   │                                 (lxc-attach self-healing provisioning)
│   ├── variables.tf                ← Spesifikasi CT (CPU, RAM, disk, IP, template)
│   ├── outputs.tf                  ← Output IP & hostname setelah apply
│   ├── download-template.tf.example← (Opsional) Auto-download Alpine template
│   └── .gitignore                  ← Exclude .terraform/, *.tfstate
│
├── index.html                    ← Halaman utama website (HTML)
├── style.css                       ← Stylesheet utama (3400+ baris)
├── script.js                       ← JavaScript interaktif (935 baris)
├── cinematic-intro.css             ← Cinematic intro animation styles
├── cinematic-intro.js              ← Cinematic intro animation logic
├── the-night-it-still-young.mp3    ← Audio asset
│
└── README.md                       ← Dokumentasi ini (kamu di sini!)
```

---

## 📋 File Workflow Detail

```
.github/workflows/deploy.yml
│
├── Trigger: push ke branch main
├── Concurrency: cancel deploy lama kalau ada push baru
│
├── 🔍 Job 0: code-validation (CI Gatekeeper)
│   ├── 📥 Checkout repository
│   ├── 🏗️ Setup Terraform (hashicorp/setup-terraform@v3)
│   ├── 🔬 HTML validation (DOCTYPE, <html>, <head>, <body>)
│   ├── 🛡️ Secret leak scan (GitHub tokens, AWS keys, private keys)
│   ├── 📦 Asset completeness (CSS/JS references exist)
│   └── 🏗️ Terraform format check (terraform fmt -check)
│
├── 🏗️ Job 1: provision (needs: code-validation)
│   ├── 📥 Checkout repository
│   ├── 🏗️ Setup Terraform (hashicorp/setup-terraform@v3)
│   ├── 🔐 Add Proxmox hosts to known_hosts (ssh-keyscan)
│   ├── 📦 Terraform Init (working-dir: terraform/)
│   └── 🚀 Terraform Apply -auto-approve
│       └── Env: TF_VAR_proxmox_api_token, TF_VAR_ssh_public_key,
│              TF_VAR_cf_tunnel_token, TF_VAR_ssh_private_key
│
└── 🚀 Job 2: deploy (needs: provision)
    ├── 📥 Checkout repository
    ├── 🔑 Setup SSH key (DEPLOY_KEY → /tmp/deploy_ssh_key)
    │   └── known_hosts: CT (111, 112) + Proxmox host (201, 202)
    ├── ⏳ SSH Readiness (self-healing, 30×5s = 150s)
    │   └── Repair: lxc-attach restart sshd + DNS + network check
    ├── 🚀 Rsync Parallel (self-healing, 30×5s = 150s)
    │   ├── --no-perms --no-owner --no-group (Alpine-safe)
    │   ├── --exclude .git* .github* terraform/
    │   └── Repair: chmod 777 + restart sshd + re-apply DNS
    ├── 🔒 Fix permissions + reload nginx (chmod 755/644)
    └── 🧹 Cleanup SSH key (always run)
```

---

## 🛡️ Catatan Keamanan

- 🔒 **JANGAN pernah commit private key ke repo.** Git history permanen — walau dihapus, tetap ada.
- 🔑 **GitHub Secrets terenkripsi** — tidak bisa dibaca setelah disimpan, bahkan oleh admin.
- 🏠 **Runner di LAN** — tidak perlu expose SSH ke internet. Semua traffic internal.
- 🧱 **Isolasi blast radius** — runner di CT dedicated, jika diexploit tidak menyebar ke web server atau hypervisor.
- 👤 **Pertimbangkan user deploy khusus** (bukan root) dengan akses terbatas ke `/var/www/html/` saja.
- 🔄 **Rotasi key berkala** — generate ulang + update Secrets jika ada indikasi kebocoran.

---

## 📝 Lisensi

Repo ini milik pribadi. Deploy dengan hati-hati. Kalau ada pertanyaan, buka issue! 😄