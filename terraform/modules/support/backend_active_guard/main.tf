locals {
  backend_active_present = fileexists(var.backend_active_tf_path)
}

resource "terraform_data" "this" {
  input = local.backend_active_present

  lifecycle {
    precondition {
      condition     = local.backend_active_present
      error_message = var.error_message
    }
  }
}
