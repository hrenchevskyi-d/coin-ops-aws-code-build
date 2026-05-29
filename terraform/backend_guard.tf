# Refuse to plan without an explicit backend.active.tf.
module "backend_active_guard" {
  source                 = "./modules/support/backend_active_guard"
  backend_active_tf_path = "${path.module}/backend.active.tf"
  error_message          = "Missing terraform/backend.active.tf. Run terraform/bootstrap-gcp.sh, terraform/bootstrap-aws.sh, or terraform/bootstrap-azure.sh before terraform plan/apply so the selected control-plane backend is explicit."
}
