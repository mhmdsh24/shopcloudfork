############################################################
# Invoice bucket - SSE-S3, block-public, versioned (required
# for replication), TLS-only policy, lifecycle expiry.
# Cross-region replication is optional.
############################################################

locals {
  tags = merge(var.tags, { Module = "s3-invoices" })
}

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = true
  tags          = merge(local.tags, { Name = var.bucket_name })
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.replica_bucket_arn != "" ? "Enabled" : "Suspended"
  }
}

# TLS-only bucket policy
data "aws_iam_policy_document" "tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "tls_only" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.tls_only.json
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = var.expire_after_days > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  rule {
    id     = "expire-old-invoices"
    status = "Enabled"

    filter {}

    expiration {
      days = var.expire_after_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# ----------------------------------------------------------
# Cross-region replication
# ----------------------------------------------------------

data "aws_iam_policy_document" "replication_assume" {
  count = var.replica_bucket_arn != "" ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "replication" {
  count              = var.replica_bucket_arn != "" ? 1 : 0
  name               = "${var.bucket_name}-replication"
  assume_role_policy = data.aws_iam_policy_document.replication_assume[0].json
  tags               = local.tags
}

data "aws_iam_policy_document" "replication" {
  count = var.replica_bucket_arn != "" ? 1 : 0

  statement {
    actions = [
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  statement {
    actions = [
      "s3:ReplicateObject",
      "s3:ReplicateDelete",
      "s3:ReplicateTags",
    ]
    resources = ["${var.replica_bucket_arn}/*"]
  }
}

resource "aws_iam_role_policy" "replication" {
  count  = var.replica_bucket_arn != "" ? 1 : 0
  name   = "${var.bucket_name}-replication"
  role   = aws_iam_role.replication[0].id
  policy = data.aws_iam_policy_document.replication[0].json
}

resource "aws_s3_bucket_replication_configuration" "this" {
  count = var.replica_bucket_arn != "" ? 1 : 0

  depends_on = [aws_s3_bucket_versioning.this]

  role   = aws_iam_role.replication[0].arn
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "replicate-all"
    status = "Enabled"

    filter {}

    delete_marker_replication {
      status = "Enabled"
    }

    destination {
      bucket        = var.replica_bucket_arn
      storage_class = "STANDARD"
    }
  }
}
