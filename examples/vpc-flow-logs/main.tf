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
    yor_trace = "738228dc-ad92-4ecc-87e3-4cbe6b168cd1"
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
    yor_trace = "48965543-dce6-4629-a649-0c054a147c04"
  }
}

resource "aws_iam_role" "vpc_flow_log_cloudwatch" {
  name_prefix        = "vpc-flow-log-role-"
  assume_role_policy = data.aws_iam_policy_document.flow_log_cloudwatch_assume_role.json
  tags = {
    Env       = "prod"
    yor_trace = "04075109-10a2-44d9-989a-5db611b6cfc8"
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
    yor_trace = "3da5b09b-e170-45ab-a4e1-f0e61669a8d1"
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
