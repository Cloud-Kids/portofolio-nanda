# ==========================================
# 📤 Output — Info yang Ditampilkan Setelah Terraform Apply
# ==========================================

output "lb1_ip" {
  description = "IP Address CT nanda-lb1 (Load Balancer 1)"
  value       = var.lb1_ip
}

output "lb2_ip" {
  description = "IP Address CT nanda-lb2 (Load Balancer 2)"
  value       = var.lb2_ip
}

output "web1_ip" {
  description = "IP Address CT web1 (Backend 1)"
  value       = var.web1_ip
}

output "web2_ip" {
  description = "IP Address CT web2 (Backend 2)"
  value       = var.web2_ip
}

output "lb1_hostname" {
  description = "Hostname CT nanda-lb1"
  value       = proxmox_virtual_environment_container.nanda_lb1.initialization[0].hostname
}

output "lb2_hostname" {
  description = "Hostname CT nanda-lb2"
  value       = proxmox_virtual_environment_container.nanda_lb2.initialization[0].hostname
}

output "web1_hostname" {
  description = "Hostname CT web1"
  value       = proxmox_virtual_environment_container.web1.initialization[0].hostname
}

output "web2_hostname" {
  description = "Hostname CT web2"
  value       = proxmox_virtual_environment_container.web2.initialization[0].hostname
}
