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
resource "terraform_data" "ssh_key_lb1" {
  input = var.ssh_public_key
}

resource "terraform_data" "ssh_key_lb2" {
  input = var.ssh_public_key
}

resource "terraform_data" "ssh_key_web1" {
  input = var.ssh_public_key
}

resource "terraform_data" "ssh_key_web2" {
  input = var.ssh_public_key
}

# ==========================================
# ⚖️ LXC LB1 — nanda-lb1 (Node: node1)
# ==========================================
resource "proxmox_virtual_environment_container" "nanda_lb1" {
  node_name    = "node1"
  vm_id        = 121
  unprivileged = true
  started      = true

  description = "CT nanda-lb1 - Load Balancer + Cloudflare Tunnel (node1)"

  initialization {
    hostname = "nanda-lb1"

    ip_config {
      ipv4 {
        address = "${var.lb1_ip}/24"
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

  lifecycle {
    replace_triggered_by = [terraform_data.ssh_key_lb1]
  }

  provisioner "remote-exec" {
    inline = [
      "until pct status 121 | grep -q 'running'; do sleep 2; done",
      "echo '✅ CT 121 running, starting network setup...'",
      "sleep 5",
      "/usr/bin/lxc-attach -n 121 -- sh -c 'ip addr flush dev eth0 2>/dev/null; ip route flush default 2>/dev/null; ip link set eth0 up; ip addr add ${var.lb1_ip}/24 dev eth0; ip route add default via 10.10.10.1 || true'",
      "echo '📡 Applied clean network config: eth0 = ${var.lb1_ip}/24, gw = 10.10.10.1'",
      "echo 'auto lo' > /tmp/net_121",
      "echo 'iface lo inet loopback' >> /tmp/net_121",
      "echo '' >> /tmp/net_121",
      "echo 'auto eth0' >> /tmp/net_121",
      "echo 'iface eth0 inet static' >> /tmp/net_121",
      "echo '    address ${var.lb1_ip}/24' >> /tmp/net_121",
      "echo '    gateway 10.10.10.1' >> /tmp/net_121",
      "echo '    dns-nameservers 1.1.1.1 8.8.8.8' >> /tmp/net_121",
      "pct push 121 /tmp/net_121 /etc/network/interfaces",
      "rm -f /tmp/net_121",
      "/usr/bin/lxc-attach -n 121 -- sh -c 'rc-service networking restart 2>/dev/null || /etc/init.d/networking restart 2>/dev/null || true'",
      "/usr/bin/lxc-attach -n 121 -- sh -c 'echo nameserver 1.1.1.1 > /etc/resolv.conf; echo nameserver 8.8.8.8 >> /etc/resolv.conf'",
      "echo '🔤 DNS configured: 1.1.1.1, 8.8.8.8'",
      "echo '#!/bin/sh' > /tmp/net_check_121.sh",
      "echo 'CT=121; ATTEMPTS=30; INTERVAL=5; OK=0; NEXT_REPAIR=8' >> /tmp/net_check_121.sh",
      "echo 'echo \"⏳ Verifying internet via apk update (TCP, max 150s)...\"' >> /tmp/net_check_121.sh",
      "echo 'for i in $(seq 1 $ATTEMPTS); do' >> /tmp/net_check_121.sh",
      "echo '  if /usr/bin/lxc-attach -n $CT -- apk update >/dev/null 2>&1; then OK=1; echo \"  attempt $i/$ATTEMPTS: SUCCESS\"; break; fi' >> /tmp/net_check_121.sh",
      "echo '  echo \"  attempt $i/$ATTEMPTS: failed\"' >> /tmp/net_check_121.sh",
      "echo '  if [ $i -ge $NEXT_REPAIR ]; then' >> /tmp/net_check_121.sh",
      "echo '    echo \"  25% checkpoint ($i/$ATTEMPTS) - re-applying DNS + restarting networking...\"' >> /tmp/net_check_121.sh",
      "echo '    /usr/bin/lxc-attach -n $CT -- sh -c \"echo nameserver 1.1.1.1 > /etc/resolv.conf; echo nameserver 8.8.8.8 >> /etc/resolv.conf\"' >> /tmp/net_check_121.sh",
      "echo '    /usr/bin/lxc-attach -n $CT -- sh -c \"rc-service networking restart 2>/dev/null || /etc/init.d/networking restart 2>/dev/null || true\"' >> /tmp/net_check_121.sh",
      "echo '    NEXT_REPAIR=$((NEXT_REPAIR + 7))' >> /tmp/net_check_121.sh",
      "echo '  fi' >> /tmp/net_check_121.sh",
      "echo '  sleep $INTERVAL' >> /tmp/net_check_121.sh",
      "echo 'done' >> /tmp/net_check_121.sh",
      "echo 'if [ $OK -ne 1 ]; then echo \"❌ CT $CT no internet after 150s!\"; exit 99; fi' >> /tmp/net_check_121.sh",
      "echo 'echo \"✅ CT $CT internet connected (TCP verified)!\"' >> /tmp/net_check_121.sh",
      "chmod +x /tmp/net_check_121.sh",
      "/bin/sh /tmp/net_check_121.sh",
      "rm -f /tmp/net_check_121.sh",
      "/usr/bin/lxc-attach -n 121 -- sh -c 'mkdir -p /run/openrc && touch /run/openrc/softlevel'",
      "/usr/bin/lxc-attach -n 121 -- apk add --no-cache openssh curl libc6-compat nginx",
      "/usr/bin/lxc-attach -n 121 -- sh -c 'sed -i \"s/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/\" /etc/ssh/sshd_config'",
      "/usr/bin/lxc-attach -n 121 -- sh -c 'sed -i \"s/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/\" /etc/ssh/sshd_config'",
      "/usr/bin/lxc-attach -n 121 -- rc-update add sshd default || true",
      "/usr/bin/lxc-attach -n 121 -- rc-service sshd restart || true",
      "echo 'upstream backend_nanda_cluster {' > /tmp/nginx_lb_121",
      "echo '    server ${var.web1_ip}:80 max_fails=3 fail_timeout=10s;' >> /tmp/nginx_lb_121",
      "echo '    server ${var.web2_ip}:80 max_fails=3 fail_timeout=10s;' >> /tmp/nginx_lb_121",
      "echo '}' >> /tmp/nginx_lb_121",
      "echo '' >> /tmp/nginx_lb_121",
      "echo 'server {' >> /tmp/nginx_lb_121",
      "echo '    listen 80;' >> /tmp/nginx_lb_121",
      "echo '    server_name nanda.smkcloud.web.id;' >> /tmp/nginx_lb_121",
      "echo '    location / {' >> /tmp/nginx_lb_121",
      "echo '        proxy_pass http://backend_nanda_cluster;' >> /tmp/nginx_lb_121",
      "echo '        proxy_set_header Host $host;' >> /tmp/nginx_lb_121",
      "echo '        proxy_set_header X-Real-IP $remote_addr;' >> /tmp/nginx_lb_121",
      "echo '        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;' >> /tmp/nginx_lb_121",
      "echo '        proxy_connect_timeout 2s;' >> /tmp/nginx_lb_121",
      "echo '        proxy_read_timeout 10s;' >> /tmp/nginx_lb_121",
      "echo '    }' >> /tmp/nginx_lb_121",
      "echo '}' >> /tmp/nginx_lb_121",
      "pct push 121 /tmp/nginx_lb_121 /etc/nginx/http.d/lb.conf",
      "rm -f /tmp/nginx_lb_121",
      "/usr/bin/lxc-attach -n 121 -- sh -c 'rm -f /etc/nginx/http.d/default.conf'",
      "/usr/bin/lxc-attach -n 121 -- rc-update add nginx default || true",
      "/usr/bin/lxc-attach -n 121 -- rc-service nginx restart || true",
      "/usr/bin/lxc-attach -n 121 -- curl -L --output /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64",
      "/usr/bin/lxc-attach -n 121 -- chmod +x /usr/local/bin/cloudflared",
      "echo '#!/sbin/openrc-run' > /tmp/cf_init_121",
      "echo 'name=\"cloudflared\"' >> /tmp/cf_init_121",
      "echo 'description=\"Cloudflare Tunnel\"' >> /tmp/cf_init_121",
      "echo 'command=\"/usr/local/bin/cloudflared\"' >> /tmp/cf_init_121",
      "echo 'command_args=\"tunnel --no-autoupdate run --token ${var.cf_tunnel_token}\"' >> /tmp/cf_init_121",
      "echo 'command_background=\"true\"' >> /tmp/cf_init_121",
      "echo 'pidfile=\"/run/cloudflared.pid\"' >> /tmp/cf_init_121",
      "echo 'depend() {' >> /tmp/cf_init_121",
      "echo '    need net' >> /tmp/cf_init_121",
      "echo '}' >> /tmp/cf_init_121",
      "pct push 121 /tmp/cf_init_121 /etc/init.d/cloudflared",
      "rm -f /tmp/cf_init_121",
      "/usr/bin/lxc-attach -n 121 -- chmod +x /etc/init.d/cloudflared",
      "/usr/bin/lxc-attach -n 121 -- rc-update add cloudflared default || true",
      "/usr/bin/lxc-attach -n 121 -- rc-service cloudflared restart || true"
    ]
  }

  connection {
    type        = "ssh"
    user        = "root"
    private_key = var.ssh_private_key
    host        = var.proxmox_node1_host
    timeout     = "10m"
  }
}

# ==========================================
# 🌐 LXC 1 — CT web1 (Node: node1)
# ==========================================
resource "proxmox_virtual_environment_container" "web1" {
  node_name    = "node1"
  vm_id        = 111
  unprivileged = true
  started      = true

  description = "CT web1 - Backend Web Server (node1)"

  initialization {
    hostname = "web1"

    ip_config {
      ipv4 {
        address = "${var.web1_ip}/24"
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
      "/usr/bin/lxc-attach -n 111 -- sh -c 'ip addr flush dev eth0 2>/dev/null; ip route flush default 2>/dev/null; ip link set eth0 up; ip addr add ${var.web1_ip}/24 dev eth0; ip route add default via 10.10.10.1 || true'",
      "echo '📡 Applied clean network config: eth0 = ${var.web1_ip}/24, gw = 10.10.10.1'",

      # 1.6. Tulis config jaringan persisten, lalu restart networking
      "echo 'auto lo' > /tmp/net_111",
      "echo 'iface lo inet loopback' >> /tmp/net_111",
      "echo '' >> /tmp/net_111",
      "echo 'auto eth0' >> /tmp/net_111",
      "echo 'iface eth0 inet static' >> /tmp/net_111",
      "echo '    address ${var.web1_ip}/24' >> /tmp/net_111",
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
      "/usr/bin/lxc-attach -n 111 -- rc-service nginx restart || true"
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
# ⚖️ LXC LB2 — nanda-lb2 (Node: node2)
# ==========================================
resource "proxmox_virtual_environment_container" "nanda_lb2" {
  node_name    = "node2"
  vm_id        = 122
  unprivileged = true
  started      = true

  description = "CT nanda-lb2 - Load Balancer + Cloudflare Tunnel (node2)"

  initialization {
    hostname = "nanda-lb2"

    ip_config {
      ipv4 {
        address = "${var.lb2_ip}/24"
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

  lifecycle {
    replace_triggered_by = [terraform_data.ssh_key_lb2]
  }

  provisioner "remote-exec" {
    inline = [
      "until pct status 122 | grep -q 'running'; do sleep 2; done",
      "echo '✅ CT 122 running, starting network setup...'",
      "sleep 5",
      "/usr/bin/lxc-attach -n 122 -- sh -c 'ip addr flush dev eth0 2>/dev/null; ip route flush default 2>/dev/null; ip link set eth0 up; ip addr add ${var.lb2_ip}/24 dev eth0; ip route add default via 10.10.10.1 || true'",
      "echo '📡 Applied clean network config: eth0 = ${var.lb2_ip}/24, gw = 10.10.10.1'",
      "echo 'auto lo' > /tmp/net_122",
      "echo 'iface lo inet loopback' >> /tmp/net_122",
      "echo '' >> /tmp/net_122",
      "echo 'auto eth0' >> /tmp/net_122",
      "echo 'iface eth0 inet static' >> /tmp/net_122",
      "echo '    address ${var.lb2_ip}/24' >> /tmp/net_122",
      "echo '    gateway 10.10.10.1' >> /tmp/net_122",
      "echo '    dns-nameservers 1.1.1.1 8.8.8.8' >> /tmp/net_122",
      "pct push 122 /tmp/net_122 /etc/network/interfaces",
      "rm -f /tmp/net_122",
      "/usr/bin/lxc-attach -n 122 -- sh -c 'rc-service networking restart 2>/dev/null || /etc/init.d/networking restart 2>/dev/null || true'",
      "/usr/bin/lxc-attach -n 122 -- sh -c 'echo nameserver 1.1.1.1 > /etc/resolv.conf; echo nameserver 8.8.8.8 >> /etc/resolv.conf'",
      "echo '🔤 DNS configured: 1.1.1.1, 8.8.8.8'",
      "echo '#!/bin/sh' > /tmp/net_check_122.sh",
      "echo 'CT=122; ATTEMPTS=30; INTERVAL=5; OK=0; NEXT_REPAIR=8' >> /tmp/net_check_122.sh",
      "echo 'echo \"⏳ Verifying internet via apk update (TCP, max 150s)...\"' >> /tmp/net_check_122.sh",
      "echo 'for i in $(seq 1 $ATTEMPTS); do' >> /tmp/net_check_122.sh",
      "echo '  if /usr/bin/lxc-attach -n $CT -- apk update >/dev/null 2>&1; then OK=1; echo \"  attempt $i/$ATTEMPTS: SUCCESS\"; break; fi' >> /tmp/net_check_122.sh",
      "echo '  echo \"  attempt $i/$ATTEMPTS: failed\"' >> /tmp/net_check_122.sh",
      "echo '  if [ $i -ge $NEXT_REPAIR ]; then' >> /tmp/net_check_122.sh",
      "echo '    echo \"  25% checkpoint ($i/$ATTEMPTS) - re-applying DNS + restarting networking...\"' >> /tmp/net_check_122.sh",
      "echo '    /usr/bin/lxc-attach -n $CT -- sh -c \"echo nameserver 1.1.1.1 > /etc/resolv.conf; echo nameserver 8.8.8.8 >> /etc/resolv.conf\"' >> /tmp/net_check_122.sh",
      "echo '    /usr/bin/lxc-attach -n $CT -- sh -c \"rc-service networking restart 2>/dev/null || /etc/init.d/networking restart 2>/dev/null || true\"' >> /tmp/net_check_122.sh",
      "echo '    NEXT_REPAIR=$((NEXT_REPAIR + 7))' >> /tmp/net_check_122.sh",
      "echo '  fi' >> /tmp/net_check_122.sh",
      "echo '  sleep $INTERVAL' >> /tmp/net_check_122.sh",
      "echo 'done' >> /tmp/net_check_122.sh",
      "echo 'if [ $OK -ne 1 ]; then echo \"❌ CT $CT no internet after 150s!\"; exit 99; fi' >> /tmp/net_check_122.sh",
      "echo 'echo \"✅ CT $CT internet connected (TCP verified)!\"' >> /tmp/net_check_122.sh",
      "chmod +x /tmp/net_check_122.sh",
      "/bin/sh /tmp/net_check_122.sh",
      "rm -f /tmp/net_check_122.sh",
      "/usr/bin/lxc-attach -n 122 -- sh -c 'mkdir -p /run/openrc && touch /run/openrc/softlevel'",
      "/usr/bin/lxc-attach -n 122 -- apk add --no-cache openssh curl libc6-compat nginx",
      "/usr/bin/lxc-attach -n 122 -- sh -c 'sed -i \"s/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/\" /etc/ssh/sshd_config'",
      "/usr/bin/lxc-attach -n 122 -- sh -c 'sed -i \"s/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/\" /etc/ssh/sshd_config'",
      "/usr/bin/lxc-attach -n 122 -- rc-update add sshd default || true",
      "/usr/bin/lxc-attach -n 122 -- rc-service sshd restart || true",
      "echo 'upstream backend_nanda_cluster {' > /tmp/nginx_lb_122",
      "echo '    server ${var.web1_ip}:80 max_fails=3 fail_timeout=10s;' >> /tmp/nginx_lb_122",
      "echo '    server ${var.web2_ip}:80 max_fails=3 fail_timeout=10s;' >> /tmp/nginx_lb_122",
      "echo '}' >> /tmp/nginx_lb_122",
      "echo '' >> /tmp/nginx_lb_122",
      "echo 'server {' >> /tmp/nginx_lb_122",
      "echo '    listen 80;' >> /tmp/nginx_lb_122",
      "echo '    server_name nanda.smkcloud.web.id;' >> /tmp/nginx_lb_122",
      "echo '    location / {' >> /tmp/nginx_lb_122",
      "echo '        proxy_pass http://backend_nanda_cluster;' >> /tmp/nginx_lb_122",
      "echo '        proxy_set_header Host $host;' >> /tmp/nginx_lb_122",
      "echo '        proxy_set_header X-Real-IP $remote_addr;' >> /tmp/nginx_lb_122",
      "echo '        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;' >> /tmp/nginx_lb_122",
      "echo '        proxy_connect_timeout 2s;' >> /tmp/nginx_lb_122",
      "echo '        proxy_read_timeout 10s;' >> /tmp/nginx_lb_122",
      "echo '    }' >> /tmp/nginx_lb_122",
      "echo '}' >> /tmp/nginx_lb_122",
      "pct push 122 /tmp/nginx_lb_122 /etc/nginx/http.d/lb.conf",
      "rm -f /tmp/nginx_lb_122",
      "/usr/bin/lxc-attach -n 122 -- sh -c 'rm -f /etc/nginx/http.d/default.conf'",
      "/usr/bin/lxc-attach -n 122 -- rc-update add nginx default || true",
      "/usr/bin/lxc-attach -n 122 -- rc-service nginx restart || true",
      "/usr/bin/lxc-attach -n 122 -- curl -L --output /usr/local/bin/cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64",
      "/usr/bin/lxc-attach -n 122 -- chmod +x /usr/local/bin/cloudflared",
      "echo '#!/sbin/openrc-run' > /tmp/cf_init_122",
      "echo 'name=\"cloudflared\"' >> /tmp/cf_init_122",
      "echo 'description=\"Cloudflare Tunnel\"' >> /tmp/cf_init_122",
      "echo 'command=\"/usr/local/bin/cloudflared\"' >> /tmp/cf_init_122",
      "echo 'command_args=\"tunnel --no-autoupdate run --token ${var.cf_tunnel_token}\"' >> /tmp/cf_init_122",
      "echo 'command_background=\"true\"' >> /tmp/cf_init_122",
      "echo 'pidfile=\"/run/cloudflared.pid\"' >> /tmp/cf_init_122",
      "echo 'depend() {' >> /tmp/cf_init_122",
      "echo '    need net' >> /tmp/cf_init_122",
      "echo '}' >> /tmp/cf_init_122",
      "pct push 122 /tmp/cf_init_122 /etc/init.d/cloudflared",
      "rm -f /tmp/cf_init_122",
      "/usr/bin/lxc-attach -n 122 -- chmod +x /etc/init.d/cloudflared",
      "/usr/bin/lxc-attach -n 122 -- rc-update add cloudflared default || true",
      "/usr/bin/lxc-attach -n 122 -- rc-service cloudflared restart || true"
    ]
  }

  connection {
    type        = "ssh"
    user        = "root"
    private_key = var.ssh_private_key
    host        = var.proxmox_node2_host
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

  description = "CT web2 - Backend Web Server (node2)"

  initialization {
    hostname = "web2"

    ip_config {
      ipv4 {
        address = "${var.web2_ip}/24"
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
      "/usr/bin/lxc-attach -n 112 -- sh -c 'ip addr flush dev eth0 2>/dev/null; ip route flush default 2>/dev/null; ip link set eth0 up; ip addr add ${var.web2_ip}/24 dev eth0; ip route add default via 10.10.10.1 || true'",
      "echo '📡 Applied clean network config: eth0 = ${var.web2_ip}/24, gw = 10.10.10.1'",

      # 1.6. Tulis config jaringan persisten, lalu restart networking
      "echo 'auto lo' > /tmp/net_112",
      "echo 'iface lo inet loopback' >> /tmp/net_112",
      "echo '' >> /tmp/net_112",
      "echo 'auto eth0' >> /tmp/net_112",
      "echo 'iface eth0 inet static' >> /tmp/net_112",
      "echo '    address ${var.web2_ip}/24' >> /tmp/net_112",
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
      "/usr/bin/lxc-attach -n 112 -- rc-service nginx restart || true"
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
