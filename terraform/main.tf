provider "aws" {
  region = "us-east-1"
}

# 1. The Financial Landing Zone (S3)
resource "aws_s3_bucket" "finops_ledger_vault" {
  bucket = "wakwetu-finops-ledger-vault-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

data "aws_caller_identity" "current" {}

# 2. S3 Public Access Block (Security Guardrail)
resource "aws_s3_bucket_public_access_block" "vault_lock" {
  bucket = aws_s3_bucket.finops_ledger_vault.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 3. S3 Bucket Policy for Billing Service
resource "aws_s3_bucket_policy" "billing_access" {
  bucket = aws_s3_bucket.finops_ledger_vault.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowBillingServiceWrite"
        Effect = "Allow"
        Principal = {
          Service = "billingreports.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.finops_ledger_vault.arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = "${data.aws_caller_identity.current.account_id}"
          }
        }
      },
      {
        Sid    = "AllowBillingServiceGetAcl"
        Effect = "Allow"
        Principal = {
          Service = "billingreports.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = "${aws_s3_bucket.finops_ledger_vault.arn}"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = "${data.aws_caller_identity.current.account_id}"
          }
        }
      }
    ]
  })
}

output "finops_bucket_name" {
  value = aws_s3_bucket.finops_ledger_vault.id
}

# 4. The Database for FinOps Metadata
resource "aws_glue_catalog_database" "finops_db" {
  name = "wakwetu_finops_db"
}

# 5. Glue Crawler (The Schema Discoverer)
# This will scan the S3 bucket to create the table structure automatically
resource "aws_iam_role" "glue_role" {
  name = "wakwetu-finops-glue-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "glue.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3_access" {
  name = "GlueS3Access"
  role = aws_iam_role.glue_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject"]
      Resource = ["${aws_s3_bucket.finops_ledger_vault.arn}/*"]
    }]
  })
}

resource "aws_glue_crawler" "finops_crawler" {
  database_name = aws_glue_catalog_database.finops_db.name
  name          = "wakwetu-billing-crawler"
  role          = aws_iam_role.glue_role.arn

  s3_target {
    path = "s3://${aws_s3_bucket.finops_ledger_vault.id}/"
  }
}

# 6. Athena Query Results Bucket
resource "aws_s3_bucket" "athena_results" {
  bucket        = "wakwetu-athena-results-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

# 7. Athena Workgroup (The Processing Engine)
resource "aws_athena_workgroup" "finops_workgroup" {
  name = "wakwetu_finops_workgroup"

  configuration {
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/"
    }
  }
}
