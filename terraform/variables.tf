# ==========================================
# 🔧 Variabel Konfigurasi — Spesifikasi Manual Kamu
# ==========================================

variable "proxmox_endpoint" {
  description = "URL API Proxmox VE (contoh: https://10.10.10.201:8006/api2/json)"
  type        = string
  default     = "https://10.10.10.201:8006/api2/json"
}

variable "proxmox_api_token" {
  description = "API Token Proxmox (format: user@realm!tokenid=secret)"
  type        = string
  sensitive   = true
}

# ── IP Management Proxmox Node (untuk SSH pct exec) ──────────────────
variable "proxmox_node1_host" {
  description = "IP SSH management node1 (tempat CT web1 & nanda-lb1 berada)"
  type        = string
  default     = "10.10.10.201"
}

variable "proxmox_node2_host" {
  description = "IP SSH management node2 (tempat CT web2 & nanda-lb2 berada)"
  type        = string
  default     = "10.10.10.202"
}

# ── IP Configuration untuk Load Balancer Containers ───────────────────
variable "lb1_ip" {
  description = "IP Address untuk nanda-lb1 (Load Balancer 1)"
  type        = string
  default     = "10.10.10.121"
}

variable "lb2_ip" {
  description = "IP Address untuk nanda-lb2 (Load Balancer 2)"
  type        = string
  default     = "10.10.10.122"
}

variable "web1_ip" {
  description = "IP Address untuk web1 (Backend 1)"
  type        = string
  default     = "10.10.10.111"
}

variable "web2_ip" {
  description = "IP Address untuk web2 (Backend 2)"
  type        = string
  default     = "10.10.10.112"
}

variable "ssh_public_key" {
  description = "SSH Public Key untuk ditanam otomatis di CT (isi dari file .pub)"
  type        = string
  sensitive   = true
}

# ── Spesifikasi Hardware CT (Ubah sesuai keinginanmu!) ──────────────
variable "ct_cpu_cores" {
  description = "Jumlah CPU core untuk setiap CT"
  type        = number
  default     = 1
}

variable "ct_memory" {
  description = "RAM dedicated untuk setiap CT (dalam MB)"
  type        = number
  default     = 128
}

variable "ct_swap" {
  description = "SWAP memory untuk setiap CT (dalam MB)"
  type        = number
  default     = 128
}

variable "ct_disk_size" {
  description = "Ukuran disk untuk setiap CT (dalam GB)"
  type        = number
  default     = 1
}

# ── Cloudflare Tunnel ───────────────────────────────────────────────
variable "cf_tunnel_token" {
  description = "Token Cloudflare Tunnel untuk replikasi HA (dari Cloudflare Zero Trust Dashboard)"
  type        = string
  sensitive   = true
}

variable "ssh_private_key" {
  description = "SSH Private Key untuk provisioner remote-exec ke Proxmox host & rsync ke CT"
  type        = string
  sensitive   = true
}

# ── OS Template ─────────────────────────────────────────────────────
variable "ct_os_template" {
  description = "Path template OS di storage Proxmox (format: storage:content-type/filename)"
  type        = string
  default     = "local:vztmpl/alpine_3.23_amd64_default.tar.xz"
}
