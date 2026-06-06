# S3 target and credentials used by CNPG Barman Cloud Plugin backups.
resource "aws_s3_bucket" "cnpg_backups" {
  count = local.aws_cnpg_backup_enabled ? 1 : 0

  bucket        = local.aws_cnpg_backup_bucket_name
  force_destroy = false

  tags = {
    Name      = local.aws_cnpg_backup_bucket_name
    Project   = local.project_name
    Component = "cnpg-backups"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "cnpg_backups" {
  count = local.aws_cnpg_backup_enabled ? 1 : 0

  bucket                  = aws_s3_bucket.cnpg_backups[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "cnpg_backups" {
  count = local.aws_cnpg_backup_enabled ? 1 : 0

  bucket = aws_s3_bucket.cnpg_backups[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cnpg_backups" {
  count = local.aws_cnpg_backup_enabled ? 1 : 0

  bucket = aws_s3_bucket.cnpg_backups[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_user" "cnpg_backup" {
  count = local.aws_cnpg_backup_enabled ? 1 : 0

  name = substr(lower("${replace(local.project_name, "_", "-")}-cnpg-backup"), 0, 64)

  tags = {
    Project   = local.project_name
    Component = "cnpg-backups"
  }
}

resource "aws_iam_user_policy" "cnpg_backup" {
  count = local.aws_cnpg_backup_enabled ? 1 : 0

  name = "${local.project_name}-cnpg-backup-s3"
  user = aws_iam_user.cnpg_backup[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.cnpg_backups[0].arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:DeleteObject",
          "s3:GetObject",
          "s3:ListMultipartUploadParts",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.cnpg_backups[0].arn}/*"
      }
    ]
  })
}

resource "aws_iam_access_key" "cnpg_backup" {
  count = local.aws_cnpg_backup_enabled ? 1 : 0

  user = aws_iam_user.cnpg_backup[0].name
}
