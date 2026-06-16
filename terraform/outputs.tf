# ==========================================
# 📤 Output — Info yang Ditampilkan Setelah Terraform Apply
# ==========================================

output "web1_ip" {
  description = "IP Address CT web1"
  value       = "10.10.10.111"
}

output "web2_ip" {
  description = "IP Address CT web2"
  value       = "10.10.10.112"
}

output "web1_hostname" {
  description = "Hostname CT web1"
  value       = proxmox_virtual_environment_container.web1.initialization[0].hostname
}

output "web2_hostname" {
  description = "Hostname CT web2"
  value       = proxmox_virtual_environment_container.web2.initialization[0].hostname
}
