provider "aws" {
  region = "us-east-1"
}

variable "project_name" {
  default = "flask-devops"
}

# S3 Bucket for Terraform State
resource "aws_s3_bucket" "state" {
  bucket = "eks-project-terraform-state-<AWS_ACCOUNT_ID>" # Change to your preferred unique name

  lifecycle {
    prevent_destroy = false # Set to true in real production
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# DynamoDB for State Locking
resource "aws_dynamodb_table" "locks" {
  name         = "terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

output "state_bucket_name" {
  value = aws_s3_bucket.state.id
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.locks.name
}
