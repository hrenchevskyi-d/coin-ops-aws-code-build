# Local files are generated handoff artifacts for the operator machine. They
# are intentionally outside remote state consumers and are gitignored.
resource "local_file" "hosts" {
  filename = var.hosts_filename
  content  = var.hosts_content
}

resource "local_file" "ssh_config" {
  filename = var.ssh_config_filename
  content  = var.ssh_config_content
}

resource "local_file" "ansible_runtime" {
  filename = var.ansible_runtime_filename
  content  = var.ansible_runtime_content
}

resource "null_resource" "sync_ssh_config" {
  count = var.sync_ssh_config ? 1 : 0

  triggers = {
    config_content = local_file.ssh_config.content
  }

  provisioner "local-exec" {
    command = <<EOT
mkdir -p ${dirname(var.ssh_sync_target_path)}
cp ${local_file.ssh_config.filename} ${var.ssh_sync_target_path}
chmod 600 ${var.ssh_sync_target_path}
EOT
  }
}
