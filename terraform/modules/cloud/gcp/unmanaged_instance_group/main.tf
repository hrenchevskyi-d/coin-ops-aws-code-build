# k3s nodes are plain compute instances, so load balancers need this unmanaged
# group as their backend adapter.
resource "google_compute_instance_group" "this" {
  name      = var.name
  zone      = var.zone
  instances = var.instances

  dynamic "named_port" {
    for_each = var.named_ports
    content {
      name = named_port.key
      port = named_port.value
    }
  }
}
