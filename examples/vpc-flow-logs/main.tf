provider "aws" {
  region = local.region
}

locals {
  name   = "ex-${replace(basename(path.cwd), "_", "-")}"
  region = "eu-west-1"

  tags = {
    Example    = local.name
    GithubRepo = "terraform-aws-vpc"
    GithubOrg  = "terraform-aws-modules"
  }

  s3_bucket_name            = "vpc-flow-logs-to-s3-${random_pet.this.id}"
  cloudwatch_log_group_name = "vpc-flow-logs-to-cloudwatch-${random_pet.this.id}"
}

################################################################################
# VPC Module
################################################################################

module "vpc_with_flow_logs_s3_bucket" {
  source = "../../"

  name = local.name
  cidr = "10.30.0.0/16"

  azs            = ["${local.region}a"]
  public_subnets = ["10.30.101.0/24"]

  enable_flow_log           = true
  flow_log_destination_type = "s3"
  flow_log_destination_arn  = module.s3_bucket.s3_bucket_arn

  vpc_flow_log_tags = local.tags
}

module "vpc_with_flow_logs_s3_bucket_parquet" {
  source = "../../"

  name = "${local.name}-parquet"
  cidr = "10.30.0.0/16"

  azs            = ["${local.region}a"]
  public_subnets = ["10.30.101.0/24"]

  enable_flow_log           = true
  flow_log_destination_type = "s3"
  flow_log_destination_arn  = module.s3_bucket.s3_bucket_arn
  flow_log_file_format      = "parquet"

  vpc_flow_log_tags = local.tags
}

# CloudWatch Log Group and IAM role created automatically
module "vpc_with_flow_logs_cloudwatch_logs_default" {
  source = "../../"

  name = "${local.name}-cloudwatch-logs-default"
  cidr = "10.10.0.0/16"

  azs            = ["${local.region}a"]
  public_subnets = ["10.10.101.0/24"]

  # Cloudwatch log group and IAM role will be created
  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 60

  vpc_flow_log_tags = local.tags
}

# CloudWatch Log Group and IAM role created separately
module "vpc_with_flow_logs_cloudwatch_logs" {
  source = "../../"

  name = "${local.name}-cloudwatch-logs"
  cidr = "10.20.0.0/16"

  azs            = ["${local.region}a"]
  public_subnets = ["10.20.101.0/24"]

  enable_flow_log                  = true
  flow_log_destination_type        = "cloud-watch-logs"
  flow_log_destination_arn         = aws_cloudwatch_log_group.flow_log.arn
  flow_log_cloudwatch_iam_role_arn = aws_iam_role.vpc_flow_log_cloudwatch.arn

  vpc_flow_log_tags = local.tags
}

################################################################################
# Supporting Resources
################################################################################

resource "random_pet" "this" {
  length = 2
}

# S3 Bucket
module "s3_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket        = local.s3_bucket_name
  policy        = data.aws_iam_policy_document.flow_log_s3.json
  force_destroy = true

  tags = merge(local.tags, {
    Env       = "prod"
    yor_trace = "7389b1b2-a035-4c0d-8d6f-65f596ff8432"
  })
}

data "aws_iam_policy_document" "flow_log_s3" {
  statement {
    sid = "AWSLogDeliveryWrite"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    resources = ["arn:aws:s3:::${local.s3_bucket_name}/AWSLogs/*"]
  }

  statement {
    sid = "AWSLogDeliveryAclCheck"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions = ["s3:GetBucketAcl"]

    resources = ["arn:aws:s3:::${local.s3_bucket_name}"]
  }
}

# Cloudwatch logs
resource "aws_cloudwatch_log_group" "flow_log" {
  name = local.cloudwatch_log_group_name
  tags = {
    Env       = "prod"
    yor_trace = "0a0886f7-8484-4e22-9d2d-398f31460dcf"
  }
}

resource "aws_iam_role" "vpc_flow_log_cloudwatch" {
  name_prefix        = "vpc-flow-log-role-"
  assume_role_policy = data.aws_iam_policy_document.flow_log_cloudwatch_assume_role.json
  tags = {
    Env       = "prod"
    yor_trace = "f0246b35-f96c-492f-9d60-65b019c0e53c"
  }
}

data "aws_iam_policy_document" "flow_log_cloudwatch_assume_role" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy_attachment" "vpc_flow_log_cloudwatch" {
  role       = aws_iam_role.vpc_flow_log_cloudwatch.name
  policy_arn = aws_iam_policy.vpc_flow_log_cloudwatch.arn
}

resource "aws_iam_policy" "vpc_flow_log_cloudwatch" {
  name_prefix = "vpc-flow-log-cloudwatch-"
  policy      = data.aws_iam_policy_document.vpc_flow_log_cloudwatch.json
  tags = {
    Env       = "prod"
    yor_trace = "28f16efb-c6de-48e7-b009-ab70147a8b76"
  }
}

data "aws_iam_policy_document" "vpc_flow_log_cloudwatch" {
  statement {
    sid = "AWSVPCFlowLogsPushToCloudWatch"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]

    resources = ["*"]
  }
}
