locals {
  # Only create flow log if user selected to create a VPC as well
  enable_flow_log = var.create_vpc && var.enable_flow_log

  create_flow_log_cloudwatch_iam_role  = local.enable_flow_log && var.flow_log_destination_type != "s3" && var.create_flow_log_cloudwatch_iam_role
  create_flow_log_cloudwatch_log_group = local.enable_flow_log && var.flow_log_destination_type != "s3" && var.create_flow_log_cloudwatch_log_group

  flow_log_destination_arn = local.create_flow_log_cloudwatch_log_group ? aws_cloudwatch_log_group.flow_log[0].arn : var.flow_log_destination_arn
  flow_log_iam_role_arn    = var.flow_log_destination_type != "s3" && local.create_flow_log_cloudwatch_iam_role ? aws_iam_role.vpc_flow_log_cloudwatch[0].arn : var.flow_log_cloudwatch_iam_role_arn
}

################################################################################
# Flow Log
################################################################################

resource "aws_flow_log" "this" {
  count = local.enable_flow_log ? 1 : 0

  log_destination_type     = var.flow_log_destination_type
  log_destination          = local.flow_log_destination_arn
  log_format               = var.flow_log_log_format
  iam_role_arn             = local.flow_log_iam_role_arn
  traffic_type             = var.flow_log_traffic_type
  vpc_id                   = local.vpc_id
  max_aggregation_interval = var.flow_log_max_aggregation_interval

  dynamic "destination_options" {
    for_each = var.flow_log_destination_type == "s3" ? [true] : []

    content {
      file_format                = var.flow_log_file_format
      hive_compatible_partitions = var.flow_log_hive_compatible_partitions
      per_hour_partition         = var.flow_log_per_hour_partition
    }
  }

  tags = merge(var.tags, var.vpc_flow_log_tags, {
    Env       = "prod"
    yor_trace = "4af924ea-7f76-4f4c-94a0-1b2869f12a02"
  })
}

################################################################################
# Flow Log CloudWatch
################################################################################

resource "aws_cloudwatch_log_group" "flow_log" {
  count = local.create_flow_log_cloudwatch_log_group ? 1 : 0

  name              = "${var.flow_log_cloudwatch_log_group_name_prefix}${local.vpc_id}"
  retention_in_days = var.flow_log_cloudwatch_log_group_retention_in_days
  kms_key_id        = var.flow_log_cloudwatch_log_group_kms_key_id

  tags = merge(var.tags, var.vpc_flow_log_tags, {
    Env       = "prod"
    yor_trace = "89c4512a-6c48-4720-847f-1ca76728c521"
  })
}

resource "aws_iam_role" "vpc_flow_log_cloudwatch" {
  count = local.create_flow_log_cloudwatch_iam_role ? 1 : 0

  name_prefix          = "vpc-flow-log-role-"
  assume_role_policy   = data.aws_iam_policy_document.flow_log_cloudwatch_assume_role[0].json
  permissions_boundary = var.vpc_flow_log_permissions_boundary

  tags = merge(var.tags, var.vpc_flow_log_tags, {
    Env       = "prod"
    yor_trace = "9ca7c83f-109f-49c8-b345-bc4bb37cb6e4"
  })
}

data "aws_iam_policy_document" "flow_log_cloudwatch_assume_role" {
  count = local.create_flow_log_cloudwatch_iam_role ? 1 : 0

  statement {
    sid = "AWSVPCFlowLogsAssumeRole"

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }

    effect = "Allow"

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy_attachment" "vpc_flow_log_cloudwatch" {
  count = local.create_flow_log_cloudwatch_iam_role ? 1 : 0

  role       = aws_iam_role.vpc_flow_log_cloudwatch[0].name
  policy_arn = aws_iam_policy.vpc_flow_log_cloudwatch[0].arn
}

resource "aws_iam_policy" "vpc_flow_log_cloudwatch" {
  count = local.create_flow_log_cloudwatch_iam_role ? 1 : 0

  name_prefix = "vpc-flow-log-to-cloudwatch-"
  policy      = data.aws_iam_policy_document.vpc_flow_log_cloudwatch[0].json
  tags = merge(var.tags, var.vpc_flow_log_tags, {
    Env       = "prod"
    yor_trace = "801e8661-8c5c-4323-bb35-4b0aa1a643d5"
  })
}

data "aws_iam_policy_document" "vpc_flow_log_cloudwatch" {
  count = local.create_flow_log_cloudwatch_iam_role ? 1 : 0

  statement {
    sid = "AWSVPCFlowLogsPushToCloudWatch"

    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]

    resources = ["*"]
  }
}
