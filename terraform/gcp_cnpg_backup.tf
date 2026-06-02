# GCS target and credentials used by CNPG Barman Cloud Plugin backups.
resource "google_storage_bucket" "cnpg_backups" {
  count = local.cnpg_backup_enabled ? 1 : 0

  name                        = local.cnpg_backup_bucket_name
  location                    = local.gcp_region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  labels = {
    app       = local.project_name
    component = "cnpg-backups"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_service_account" "cnpg_backup" {
  count = local.cnpg_backup_enabled ? 1 : 0

  account_id   = substr(lower("${replace(local.project_name, "_", "-")}-cnpg-backup"), 0, 30)
  display_name = "${local.project_name} CNPG backup writer"
  description  = "Writes CloudNativePG Barman Cloud backups to the Coin-Ops GCS bucket."
}

resource "google_storage_bucket_iam_member" "cnpg_backup_object_admin" {
  count = local.cnpg_backup_enabled ? 1 : 0

  bucket = google_storage_bucket.cnpg_backups[0].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.cnpg_backup[0].email}"
}

resource "google_storage_bucket_iam_member" "cnpg_backup_bucket_reader" {
  count = local.cnpg_backup_enabled ? 1 : 0

  bucket = google_storage_bucket.cnpg_backups[0].name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${google_service_account.cnpg_backup[0].email}"
}

resource "google_service_account_key" "cnpg_backup" {
  count = local.cnpg_backup_enabled ? 1 : 0

  service_account_id = google_service_account.cnpg_backup[0].name
}
