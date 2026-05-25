output "hosts_filename" {
  value = local_file.hosts.filename
}

output "ssh_config_filename" {
  value = local_file.ssh_config.filename
}

output "ssh_config_content" {
  value = local_file.ssh_config.content
}

output "ansible_runtime_filename" {
  value = local_file.ansible_runtime.filename
}
