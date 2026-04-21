# ╔══════════════════════════════════════════════════════════════╗
# ║  terraform/lms/main.tf — LAB 4 TARGET                      ║
# ║                                                              ║
# ║  This file contains THREE deliberate misconfigurations.     ║
# ║  Your task:                                                  ║
# ║    1. Run: checkov -d . --compact                           ║
# ║    2. Identify the FAILED checks                            ║
# ║    3. Apply the fixes (comments guide you)                  ║
# ║    4. Re-run checkov — confirm 0 FAILED                     ║
# ╚══════════════════════════════════════════════════════════════╝

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}



provider "aws" {
  region = var.aws_region
}

variable "aws_region"   { default = "ap-south-1" }
variable "db_password"  { sensitive = true }

# ── VPC & Networking (already secure — for reference) ────────────────────────
resource "aws_vpc" "lms_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "lms-vpc", Project = "lms", Team = "devops" }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.lms_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.aws_region}a"
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.lms_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}b"
}

resource "aws_db_subnet_group" "private" {
  name       = "lms-private-subnets"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

# ── MISCONFIGURATION 1: RDS — publicly accessible ────────────────────────────
# Checkov: CKV_AWS_17 "Ensure all data stored in the RDS instance is not publicly accessible"
# Checkov: CKV_AWS_129 "Ensure that respective logs of Amazon RDS are enabled"
# Checkov: CKV_AWS_133 "Ensure that RDS instances has backup enabled"
#
# FIX: set publicly_accessible = false, storage_encrypted = true,
#      deletion_protection = true, multi_az = true, backup_retention_period = 7
resource "aws_db_instance" "lms_mysql" {
  identifier        = "lms-mysql"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.medium"
  allocated_storage = 20

  db_name  = "lmsdb"
  username = "admin"
  password = var.db_password      # correct — using variable, not hardcoded

  # ← MISCONFIGURATION: database is reachable from the internet
  publicly_accessible = true

  # ← MISCONFIGURATION: data not encrypted at rest
  storage_encrypted = false

  # ← MISCONFIGURATION: no deletion protection
  deletion_protection = false

  # ← MISCONFIGURATION: no Multi-AZ (also caught by custom CKV_SBI_001)
  multi_az = false

  db_subnet_group_name   = aws_db_subnet_group.private.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true

  tags = { Project = "lms", Environment = "prod" }
}

# ── MISCONFIGURATION 2: S3 bucket — public read ──────────────────────────────
# Checkov: CKV_AWS_53 "Ensure S3 bucket has block public ACLS enabled"
# Checkov: CKV_AWS_54 "Ensure S3 bucket has block public policy enabled"
# Checkov: CKV_AWS_55 "Ensure S3 bucket has ignore public ACLs enabled"
# Checkov: CKV_AWS_56 "Ensure S3 bucket has restrict_public_buckets enabled"
# Checkov: CKV2_AWS_6 "Ensure that S3 bucket has a Public Access block"
#
# FIX: replace the acl resource with aws_s3_bucket_public_access_block
#      and add aws_s3_bucket_server_side_encryption_configuration
resource "aws_s3_bucket" "lms_reports" {
  bucket = "sbi-lms-reports-${var.aws_region}"
  tags   = { Project = "lms", DataClassification = "Confidential" }
}

# ← MISCONFIGURATION: bucket is publicly readable — exposes loan reports
resource "aws_s3_bucket_acl" "lms_reports_acl" {
  bucket = aws_s3_bucket.lms_reports.id
  acl    = "public-read"
}

# FIX (uncomment and remove the acl resource above):
# resource "aws_s3_bucket_public_access_block" "lms_reports" {
#   bucket                  = aws_s3_bucket.lms_reports.id
#   block_public_acls       = true
#   block_public_policy     = true
#   ignore_public_acls      = true
#   restrict_public_buckets = true
# }
#
# resource "aws_s3_bucket_server_side_encryption_configuration" "lms_enc" {
#   bucket = aws_s3_bucket.lms_reports.id
#   rule {
#     apply_server_side_encryption_by_default {
#       sse_algorithm = "aws:kms"
#     }
#   }
# }

# ── MISCONFIGURATION 3: Security Group — all traffic allowed ─────────────────
# Checkov: CKV_AWS_25  "Ensure no security groups allow ingress from 0.0.0.0:0 to port 22"
# Checkov: CKV_AWS_277 "Ensure no security groups allow ingress from 0.0.0.0/0 to all ports"
#
# FIX: restrict ingress to only port 443 from internet;
#      port 8080 only from the load balancer security group
resource "aws_security_group" "lms_sg" {
  name        = "lms-app-sg"
  description = "LMS application security group"
  vpc_id      = aws_vpc.lms_vpc.id

  # ← MISCONFIGURATION: allows ALL inbound traffic from anywhere
  ingress {
    description = "All traffic — DO NOT USE IN PRODUCTION"
    from_port   = 0
    to_port     = 65535
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Project = "lms" }
}

# FIX (replace the ingress block above with these two):
# ingress {
#   description = "HTTPS from internet"
#   from_port   = 443
#   to_port     = 443
#   protocol    = "tcp"
#   cidr_blocks = ["0.0.0.0/0"]
# }
# ingress {
#   description     = "App port from load balancer only"
#   from_port       = 8080
#   to_port         = 8080
#   protocol        = "tcp"
#   security_groups = [aws_security_group.alb_sg.id]
# }

resource "aws_security_group" "rds_sg" {
  name        = "lms-rds-sg"
  description = "RDS security group — allow MySQL only from app SG"
  vpc_id      = aws_vpc.lms_vpc.id

  ingress {
    description     = "MySQL from app tier only"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.lms_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Project = "lms" }
}
