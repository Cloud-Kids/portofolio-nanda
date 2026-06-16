# https://registry.terraform.io/providers/bpg/proxmox/0.109.0
terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.109.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true
}

# ==========================================
# 🔑 SSH Key Trackers (trigger CT replace on key change)
# ==========================================
resource "terraform_data" "ssh_key_web1" {
  input = var.ssh_public_key
}

resource "terraform_data" "ssh_key_web2" {
  input = var.ssh_public_key
}

# ==========================================
# 🌐 LXC 1 — CT web1 (Node: node1)
# ==========================================
resource "proxmox_virtual_environment_container" "web1" {
  node_name    = "node1"
  vm_id        = 111
  unprivileged = true
  started      = true

  description = "CT web1 - Active-Active Edge Node (node1)"

  initialization {
    hostname = "web1"

    ip_config {
      ipv4 {
        address = "10.10.10.111/24"
        gateway = "10.10.10.1"
      }
    }

    user_account {
      keys = [var.ssh_public_key]
    }
  }

  cpu {
    cores = var.ct_cpu_cores
  }

  memory {
    dedicated = var.ct_memory
    swap      = var.ct_swap
  }

  disk {
    datastore_id = "local-lvm"
    size         = var.ct_disk_size
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  operating_system {
    template_file_id = var.ct_os_template
    type             = "alpine"
  }

  features {
    nesting = true
  }

  # Force recreate CTs when SSH key changes (GitHub Secret update)
  lifecycle {
    replace_triggered_by = [terraform_data.ssh_key_web1]
  }

  # ── Host-Based Provisioning: SSH ke Proxmox host → lxc-attach ke dalam CT ──
  # lxc-attach bypass bug Perl pct exec yang hang 100% CPU di Alpine unprivileged.
  provisioner "remote-exec" {
    inline = [
      # 1. Tunggu CT benar-benar running
      "until pct status 111 | grep -q 'running'; do sleep 2; done",
      "echo '✅ CT 111 running, starting network setup...'",

      # 1.5. FLUSH config lama, lalu setup jaringan bersih (Alpine template bisa punya DHCP/conflicting IP)
      "sleep 5",
      "/usr/bin/lxc-attach -n 111 -- sh -c 'ip addr flush dev eth0 2>/dev/null; ip route flush default 2>/dev/null; ip link set eth0 up; ip addr add 10.10.10.111/24 dev eth0; ip route add default via 10.10.10.1 || true'",
      "echo '📡 Applied clean network config: eth0 = 10.10.10.111/24, gw = 10.10.10.1'",

      # 1.6. Tulis config jaringan persisten, lalu restart networking
      "echo 'auto lo' > /tmp/net_111",
      "echo 'iface lo inet loopback' >> /tmp/net_111",
      "echo '' >> /tmp/net_111",
      "echo 'auto eth0' >> /tmp/net_111",
      "echo 'iface eth0 inet static' >> /tmp/net_111",
      "echo '    address 10.10.10.111/24' >> /tmp/net_111",
      "echo '    gateway 10.10.10.1' >> /tmp/net_111",
      "echo '    dns-nameservers 1.1.1.1 8.8.8.8' >> /tmp/net_111",
      "pct push 111 /tmp/net_111 /etc/network/interfaces",
      "rm -f /tmp/net_111",
      "/usr/bin/lxc-attach -n 111 -- sh -c 'rc-service networking restart 2>/dev/null || /etc/init.d/networking restart 2>/dev/null || true'",

      # 1.65. Setup DNS (tanpa nameserver, apk update gagal resolve repo)
      "/usr/bin/lxc-attach -n 111 -- sh -c 'echo nameserver 1.1.1.1 > /etc/resolv.conf; echo nameserver 8.8.8.8 >> /etc/resolv.conf'",
      "echo '🔤 DNS configured: 1.1.1.1, 8.8.8.8'",

      # 1.7. Diagnostic snapshot ke host (bisa dibaca via SSH jika pipeline gagal)
      "sh -c 'echo \"=== Provision diagnostic CT 111 ===\" > /tmp/provision_diag_111.log'",
      "sh -c 'echo \"--- ip addr show eth0 ---\" >> /tmp/provision_diag_111.log'",
      "/usr/bin/lxc-attach -n 111 -- ip addr show eth0 >> /tmp/provision_diag_111.log 2>&1 || true",
      "sh -c 'echo \"--- ip route ---\" >> /tmp/provision_diag_111.log'",
      "/usr/bin/lxc-attach -n 111 -- ip route >> /tmp/provision_diag_111.log 2>&1 || true",
      "sh -c 'echo \"--- ping gateway ---\" >> /tmp/provision_diag_111.log'",
      "/usr/bin/lxc-attach -n 111 -- ping -c 2 10.10.10.1 >> /tmp/provision_diag_111.log 2>&1 || true",
      "sh -c 'echo \"--- DNS resolve test ---\" >> /tmp/provision_diag_111.log'",
      "/usr/bin/lxc-attach -n 111 -- sh -c 'cat /etc/resolv.conf; nslookup dl-cdn.alpinelinux.org 2>&1 || true' >> /tmp/provision_diag_111.log 2>&1 || true",

      # 2. Self-healing internet check: tulis script ke host, lalu execute
      #    30 attempt × 5s = 150s total. Setiap 25% (attempt 8, 15, 23) auto-repair DNS+networking.
      "echo '#!/bin/sh' > /tmp/net_check_111.sh",
      "echo 'CT=111; ATTEMPTS=30; INTERVAL=5; OK=0; NEXT_REPAIR=8' >> /tmp/net_check_111.sh",
      "echo 'echo \"⏳ Verifying internet via apk update (TCP, max 150s)...\"' >> /tmp/net_check_111.sh",
      "echo 'for i in $(seq 1 $ATTEMPTS); do' >> /tmp/net_check_111.sh",
      "echo '  if /usr/bin/lxc-attach -n $CT -- apk update >/dev/null 2>&1; then OK=1; echo \"  attempt $i/$ATTEMPTS: SUCCESS\"; break; fi' >> /tmp/net_check_111.sh",
      "echo '  echo \"  attempt $i/$ATTEMPTS: failed\"' >> /tmp/net_check_111.sh",
      "echo '  if [ $i -ge $NEXT_REPAIR ]; then' >> /tmp/net_check_111.sh",
      "echo '    echo \"  25% checkpoint ($i/$ATTEMPTS) - re-applying DNS + restarting networking...\"' >> /tmp/net_check_111.sh",
      "echo '    /usr/bin/lxc-attach -n $CT -- sh -c \"echo nameserver 1.1.1.1 > /etc/resolv.conf; echo nameserver 8.8.8.8 >> /etc/resolv.conf\"' >> /tmp/net_check_111.sh",
      "echo '    /usr/bin/lxc-attach -n $CT -- sh -c \"rc-service networking restart 2>/dev/null || /etc/init.d/networking restart 2>/dev/null || true\"' >> /tmp/net_check_111.sh",
      "echo '    NEXT_REPAIR=$((NEXT_REPAIR + 7))' >> /tmp/net_check_111.sh",
      "echo '  fi' >> /tmp/net_check_111.sh",
      "echo '  sleep $INTERVAL' >> /tmp/net_check_111.sh",
      "echo 'done' >> /tmp/net_check_111.sh",
      "echo 'if [ $OK -ne 1 ]; then echo \"❌ CT $CT no internet after 150s! Check /tmp/provision_diag_$CT.log\"; exit 99; fi' >> /tmp/net_check_111.sh",
      "echo 'echo \"✅ CT $CT internet connected (TCP verified)!\"' >> /tmp/net_check_111.sh",
      "chmod +x /tmp/net_check_111.sh",
      "/bin/sh /tmp/net_check_111.sh",
      "rm -f /tmp/net_check_111.sh",

      # 3. Inisialisasi OpenRC (fix 'softlevel not set')
      "/usr/bin/lxc-attach -n 111 -- sh -c 'mkdir -p /run/openrc && touch /run/openrc/softlevel'",

      # 4. Install semua paket sekaligus (satu kali download index apk — hemat ~20s)
      "/usr/bin/lxc-attach -n 111 -- apk add --no-cache openssh curl libc6-compat rsync openrc nginx",

      # 5. Konfigurasi & start SSH
      "/usr/bin/lxc-attach -n 111 -- sh -c 'sed -i \"s/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/\" /etc/ssh/sshd_config'",
      "/usr/bin/lxc-attach -n 111 -- sh -c 'sed -i \"s/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/\" /etc/ssh/sshd_config'",
      "/usr/bin/lxc-attach -n 111 -- rc-update add sshd default || true",
      "/usr/bin/lxc-attach -n 111 -- rc-service sshd restart || true",

      # 5.5. Buat web root directory + chmod 777 (rsync user perlu tulis)
      "/usr/bin/lxc-attach -n 111 -- sh -c 'mkdir -p /var/www/html && chmod -R 777 /var/www/html'",

      # 5.6. Konfigurasi nginx (serve /var/www/html di port 80) — nginx sudah terinstall di step 4
      "echo 'server {' > /tmp/nginx_111",
      "echo '    listen 80 default_server;' >> /tmp/nginx_111",
      "echo '    listen [::]:80 default_server;' >> /tmp/nginx_111",
      "echo '    root /var/www/html;' >> /tmp/nginx_111",
      "echo '    index index.html index.htm;' >> /tmp/nginx_111",
      "echo '    server_name _;' >> /tmp/nginx_111",
      "echo '    location / {' >> /tmp/nginx_111",
      "echo '        try_files $uri $uri/ =404;' >> /tmp/nginx_111",
      "echo '    }' >> /tmp/nginx_111",
      "echo '}' >> /tmp/nginx_111",
      "pct push 111 /tmp/nginx_111 /etc/nginx/http.d/default.conf",
      "rm -f /tmp/nginx_111",
      "/usr/bin/lxc-attach -n 111 -- rc-update add nginx default || true",
      "/usr/bin/lxc-attach -n 111 -- rc-service nginx restart || true",

      # 6. Download cloudflared binary
      "/usr/bin/lxc-attach -n 111 -- curl -L --output /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64",
      "/usr/bin/lxc-attach -n 111 -- chmod +x /usr/local/bin/cloudflared",

      # 7. Buat OpenRC init script di HOST (hindari escaping issues di lxc-attach)
      "echo '#!/sbin/openrc-run' > /tmp/cf_init_111",
      "echo 'name=\"cloudflared\"' >> /tmp/cf_init_111",
      "echo 'description=\"Cloudflare Tunnel\"' >> /tmp/cf_init_111",
      "echo 'command=\"/usr/local/bin/cloudflared\"' >> /tmp/cf_init_111",
      "echo 'command_args=\"tunnel --no-autoupdate run --token ${var.cf_tunnel_token}\"' >> /tmp/cf_init_111",
      "echo 'command_background=\"true\"' >> /tmp/cf_init_111",
      "echo 'pidfile=\"/run/cloudflared.pid\"' >> /tmp/cf_init_111",
      "echo 'depend() {' >> /tmp/cf_init_111",
      "echo '    need net' >> /tmp/cf_init_111",
      "echo '}' >> /tmp/cf_init_111",

      # 8. Push init script dari host ke dalam CT via pct push
      "pct push 111 /tmp/cf_init_111 /etc/init.d/cloudflared",
      "rm -f /tmp/cf_init_111",

      # 9. Start cloudflared service
      "/usr/bin/lxc-attach -n 111 -- chmod +x /etc/init.d/cloudflared",
      "/usr/bin/lxc-attach -n 111 -- rc-update add cloudflared default || true",
      "/usr/bin/lxc-attach -n 111 -- rc-service cloudflared restart || true"
    ]
  }

  # SSH ke Proxmox host, BUKAN ke CT langsung
  connection {
    type        = "ssh"
    user        = "root"
    private_key = var.ssh_private_key
    host        = var.proxmox_node1_host
    timeout     = "10m"
  }
}

# ==========================================
# 🌐 LXC 2 — CT web2 (Node: node2)
# ==========================================
resource "proxmox_virtual_environment_container" "web2" {
  node_name    = "node2"
  vm_id        = 112
  unprivileged = true
  started      = true

  description = "CT web2 - Active-Active Edge Node (node2)"

  initialization {
    hostname = "web2"

    ip_config {
      ipv4 {
        address = "10.10.10.112/24"
        gateway = "10.10.10.1"
      }
    }

    user_account {
      keys = [var.ssh_public_key]
    }
  }

  cpu {
    cores = var.ct_cpu_cores
  }

  memory {
    dedicated = var.ct_memory
    swap      = var.ct_swap
  }

  disk {
    datastore_id = "local-lvm"
    size         = var.ct_disk_size
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  operating_system {
    template_file_id = var.ct_os_template
    type             = "alpine"
  }

  features {
    nesting = true
  }

  # Force recreate CTs when SSH key changes (GitHub Secret update)
  lifecycle {
    replace_triggered_by = [terraform_data.ssh_key_web2]
  }

  # ── Host-Based Provisioning: SSH ke Proxmox host → lxc-attach ke dalam CT ──
  provisioner "remote-exec" {
    inline = [
      # 1. Tunggu CT benar-benar running
      "until pct status 112 | grep -q 'running'; do sleep 2; done",
      "echo '✅ CT 112 running, starting network setup...'",

      # 1.5. FLUSH config lama, lalu setup jaringan bersih (Alpine template bisa punya DHCP/conflicting IP)
      "sleep 5",
      "/usr/bin/lxc-attach -n 112 -- sh -c 'ip addr flush dev eth0 2>/dev/null; ip route flush default 2>/dev/null; ip link set eth0 up; ip addr add 10.10.10.112/24 dev eth0; ip route add default via 10.10.10.1 || true'",
      "echo '📡 Applied clean network config: eth0 = 10.10.10.112/24, gw = 10.10.10.1'",

      # 1.6. Tulis config jaringan persisten, lalu restart networking
      "echo 'auto lo' > /tmp/net_112",
      "echo 'iface lo inet loopback' >> /tmp/net_112",
      "echo '' >> /tmp/net_112",
      "echo 'auto eth0' >> /tmp/net_112",
      "echo 'iface eth0 inet static' >> /tmp/net_112",
      "echo '    address 10.10.10.112/24' >> /tmp/net_112",
      "echo '    gateway 10.10.10.1' >> /tmp/net_112",
      "echo '    dns-nameservers 1.1.1.1 8.8.8.8' >> /tmp/net_112",
      "pct push 112 /tmp/net_112 /etc/network/interfaces",
      "rm -f /tmp/net_112",
      "/usr/bin/lxc-attach -n 112 -- sh -c 'rc-service networking restart 2>/dev/null || /etc/init.d/networking restart 2>/dev/null || true'",

      # 1.65. Setup DNS (tanpa nameserver, apk update gagal resolve repo)
      "/usr/bin/lxc-attach -n 112 -- sh -c 'echo nameserver 1.1.1.1 > /etc/resolv.conf; echo nameserver 8.8.8.8 >> /etc/resolv.conf'",
      "echo '🔤 DNS configured: 1.1.1.1, 8.8.8.8'",

      # 1.7. Diagnostic snapshot ke host (bisa dibaca via SSH jika pipeline gagal)
      "sh -c 'echo \"=== Provision diagnostic CT 112 ===\" > /tmp/provision_diag_112.log'",
      "sh -c 'echo \"--- ip addr show eth0 ---\" >> /tmp/provision_diag_112.log'",
      "/usr/bin/lxc-attach -n 112 -- ip addr show eth0 >> /tmp/provision_diag_112.log 2>&1 || true",
      "sh -c 'echo \"--- ip route ---\" >> /tmp/provision_diag_112.log'",
      "/usr/bin/lxc-attach -n 112 -- ip route >> /tmp/provision_diag_112.log 2>&1 || true",
      "sh -c 'echo \"--- ping gateway ---\" >> /tmp/provision_diag_112.log'",
      "/usr/bin/lxc-attach -n 112 -- ping -c 2 10.10.10.1 >> /tmp/provision_diag_112.log 2>&1 || true",
      "sh -c 'echo \"--- DNS resolve test ---\" >> /tmp/provision_diag_112.log'",
      "/usr/bin/lxc-attach -n 112 -- sh -c 'cat /etc/resolv.conf; nslookup dl-cdn.alpinelinux.org 2>&1 || true' >> /tmp/provision_diag_112.log 2>&1 || true",

      # 2. Self-healing internet check: tulis script ke host, lalu execute
      #    30 attempt × 5s = 150s total. Setiap 25% (attempt 8, 15, 23) auto-repair DNS+networking.
      "echo '#!/bin/sh' > /tmp/net_check_112.sh",
      "echo 'CT=112; ATTEMPTS=30; INTERVAL=5; OK=0; NEXT_REPAIR=8' >> /tmp/net_check_112.sh",
      "echo 'echo \"⏳ Verifying internet via apk update (TCP, max 150s)...\"' >> /tmp/net_check_112.sh",
      "echo 'for i in $(seq 1 $ATTEMPTS); do' >> /tmp/net_check_112.sh",
      "echo '  if /usr/bin/lxc-attach -n $CT -- apk update >/dev/null 2>&1; then OK=1; echo \"  attempt $i/$ATTEMPTS: SUCCESS\"; break; fi' >> /tmp/net_check_112.sh",
      "echo '  echo \"  attempt $i/$ATTEMPTS: failed\"' >> /tmp/net_check_112.sh",
      "echo '  if [ $i -ge $NEXT_REPAIR ]; then' >> /tmp/net_check_112.sh",
      "echo '    echo \"  25% checkpoint ($i/$ATTEMPTS) - re-applying DNS + restarting networking...\"' >> /tmp/net_check_112.sh",
      "echo '    /usr/bin/lxc-attach -n $CT -- sh -c \"echo nameserver 1.1.1.1 > /etc/resolv.conf; echo nameserver 8.8.8.8 >> /etc/resolv.conf\"' >> /tmp/net_check_112.sh",
      "echo '    /usr/bin/lxc-attach -n $CT -- sh -c \"rc-service networking restart 2>/dev/null || /etc/init.d/networking restart 2>/dev/null || true\"' >> /tmp/net_check_112.sh",
      "echo '    NEXT_REPAIR=$((NEXT_REPAIR + 7))' >> /tmp/net_check_112.sh",
      "echo '  fi' >> /tmp/net_check_112.sh",
      "echo '  sleep $INTERVAL' >> /tmp/net_check_112.sh",
      "echo 'done' >> /tmp/net_check_112.sh",
      "echo 'if [ $OK -ne 1 ]; then echo \"❌ CT $CT no internet after 150s! Check /tmp/provision_diag_$CT.log\"; exit 99; fi' >> /tmp/net_check_112.sh",
      "echo 'echo \"✅ CT $CT internet connected (TCP verified)!\"' >> /tmp/net_check_112.sh",
      "chmod +x /tmp/net_check_112.sh",
      "/bin/sh /tmp/net_check_112.sh",
      "rm -f /tmp/net_check_112.sh",

      # 3. Inisialisasi OpenRC (fix 'softlevel not set')
      "/usr/bin/lxc-attach -n 112 -- sh -c 'mkdir -p /run/openrc && touch /run/openrc/softlevel'",

      # 4. Install semua paket sekaligus (satu kali download index apk — hemat ~20s)
      "/usr/bin/lxc-attach -n 112 -- apk add --no-cache openssh curl libc6-compat rsync openrc nginx",

      # 5. Konfigurasi & start SSH
      "/usr/bin/lxc-attach -n 112 -- sh -c 'sed -i \"s/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/\" /etc/ssh/sshd_config'",
      "/usr/bin/lxc-attach -n 112 -- sh -c 'sed -i \"s/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/\" /etc/ssh/sshd_config'",
      "/usr/bin/lxc-attach -n 112 -- rc-update add sshd default || true",
      "/usr/bin/lxc-attach -n 112 -- rc-service sshd restart || true",

      # 5.5. Buat web root directory + chmod 777 (rsync user perlu tulis)
      "/usr/bin/lxc-attach -n 112 -- sh -c 'mkdir -p /var/www/html && chmod -R 777 /var/www/html'",

      # 5.6. Konfigurasi nginx (serve /var/www/html di port 80) — nginx sudah terinstall di step 4
      "echo 'server {' > /tmp/nginx_112",
      "echo '    listen 80 default_server;' >> /tmp/nginx_112",
      "echo '    listen [::]:80 default_server;' >> /tmp/nginx_112",
      "echo '    root /var/www/html;' >> /tmp/nginx_112",
      "echo '    index index.html index.htm;' >> /tmp/nginx_112",
      "echo '    server_name _;' >> /tmp/nginx_112",
      "echo '    location / {' >> /tmp/nginx_112",
      "echo '        try_files $uri $uri/ =404;' >> /tmp/nginx_112",
      "echo '    }' >> /tmp/nginx_112",
      "echo '}' >> /tmp/nginx_112",
      "pct push 112 /tmp/nginx_112 /etc/nginx/http.d/default.conf",
      "rm -f /tmp/nginx_112",
      "/usr/bin/lxc-attach -n 112 -- rc-update add nginx default || true",
      "/usr/bin/lxc-attach -n 112 -- rc-service nginx restart || true",

      # 6. Download cloudflared binary
      "/usr/bin/lxc-attach -n 112 -- curl -L --output /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64",
      "/usr/bin/lxc-attach -n 112 -- chmod +x /usr/local/bin/cloudflared",

      # 7. Buat OpenRC init script di HOST (hindari escaping issues di lxc-attach)
      "echo '#!/sbin/openrc-run' > /tmp/cf_init_112",
      "echo 'name=\"cloudflared\"' >> /tmp/cf_init_112",
      "echo 'description=\"Cloudflare Tunnel\"' >> /tmp/cf_init_112",
      "echo 'command=\"/usr/local/bin/cloudflared\"' >> /tmp/cf_init_112",
      "echo 'command_args=\"tunnel --no-autoupdate run --token ${var.cf_tunnel_token}\"' >> /tmp/cf_init_112",
      "echo 'command_background=\"true\"' >> /tmp/cf_init_112",
      "echo 'pidfile=\"/run/cloudflared.pid\"' >> /tmp/cf_init_112",
      "echo 'depend() {' >> /tmp/cf_init_112",
      "echo '    need net' >> /tmp/cf_init_112",
      "echo '}' >> /tmp/cf_init_112",

      # 8. Push init script dari host ke dalam CT via pct push
      "pct push 112 /tmp/cf_init_112 /etc/init.d/cloudflared",
      "rm -f /tmp/cf_init_112",

      # 9. Start cloudflared service
      "/usr/bin/lxc-attach -n 112 -- chmod +x /etc/init.d/cloudflared",
      "/usr/bin/lxc-attach -n 112 -- rc-update add cloudflared default || true",
      "/usr/bin/lxc-attach -n 112 -- rc-service cloudflared restart || true"
    ]
  }

  # SSH ke Proxmox host node2, BUKAN ke CT langsung
  connection {
    type        = "ssh"
    user        = "root"
    private_key = var.ssh_private_key
    host        = var.proxmox_node2_host
    timeout     = "10m"
  }
}
