locals {
  max_subnet_length = max(
    length(var.private_subnets),
    length(var.elasticache_subnets),
    length(var.database_subnets),
    length(var.redshift_subnets),
  )
  nat_gateway_count = var.single_nat_gateway ? 1 : var.one_nat_gateway_per_az ? length(var.azs) : local.max_subnet_length

  # Use `local.vpc_id` to give a hint to Terraform that subnets should be deleted before secondary CIDR blocks can be free!
  vpc_id = try(aws_vpc_ipv4_cidr_block_association.this[0].vpc_id, aws_vpc.this[0].id, "")

  create_vpc = var.create_vpc && var.putin_khuylo
}

################################################################################
# VPC
################################################################################

resource "aws_vpc" "this" {
  count = local.create_vpc ? 1 : 0

  cidr_block          = var.use_ipam_pool ? null : var.cidr
  ipv4_ipam_pool_id   = var.ipv4_ipam_pool_id
  ipv4_netmask_length = var.ipv4_netmask_length

  assign_generated_ipv6_cidr_block = var.enable_ipv6 && !var.use_ipam_pool ? true : null
  ipv6_cidr_block                  = var.ipv6_cidr
  ipv6_ipam_pool_id                = var.ipv6_ipam_pool_id
  ipv6_netmask_length              = var.ipv6_netmask_length

  instance_tenancy               = var.instance_tenancy
  enable_dns_hostnames           = var.enable_dns_hostnames
  enable_dns_support             = var.enable_dns_support
  enable_classiclink             = null # https://github.com/hashicorp/terraform/issues/31730
  enable_classiclink_dns_support = null # https://github.com/hashicorp/terraform/issues/31730

  tags = merge(
    { "Name" = var.name },
    var.tags,
    var.vpc_tags,
    {
      Env       = "prod"
      yor_trace = "286d6a3c-97f1-45a0-8ea9-bde3932012a9"
  })
}

resource "aws_vpc_ipv4_cidr_block_association" "this" {
  count = local.create_vpc && length(var.secondary_cidr_blocks) > 0 ? length(var.secondary_cidr_blocks) : 0

  # Do not turn this into `local.vpc_id`
  vpc_id = aws_vpc.this[0].id

  cidr_block = element(var.secondary_cidr_blocks, count.index)
}

resource "aws_default_security_group" "this" {
  count = local.create_vpc && var.manage_default_security_group ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  dynamic "ingress" {
    for_each = var.default_security_group_ingress
    content {
      self             = lookup(ingress.value, "self", null)
      cidr_blocks      = compact(split(",", lookup(ingress.value, "cidr_blocks", "")))
      ipv6_cidr_blocks = compact(split(",", lookup(ingress.value, "ipv6_cidr_blocks", "")))
      prefix_list_ids  = compact(split(",", lookup(ingress.value, "prefix_list_ids", "")))
      security_groups  = compact(split(",", lookup(ingress.value, "security_groups", "")))
      description      = lookup(ingress.value, "description", null)
      from_port        = lookup(ingress.value, "from_port", 0)
      to_port          = lookup(ingress.value, "to_port", 0)
      protocol         = lookup(ingress.value, "protocol", "-1")
    }
  }

  dynamic "egress" {
    for_each = var.default_security_group_egress
    content {
      self             = lookup(egress.value, "self", null)
      cidr_blocks      = compact(split(",", lookup(egress.value, "cidr_blocks", "")))
      ipv6_cidr_blocks = compact(split(",", lookup(egress.value, "ipv6_cidr_blocks", "")))
      prefix_list_ids  = compact(split(",", lookup(egress.value, "prefix_list_ids", "")))
      security_groups  = compact(split(",", lookup(egress.value, "security_groups", "")))
      description      = lookup(egress.value, "description", null)
      from_port        = lookup(egress.value, "from_port", 0)
      to_port          = lookup(egress.value, "to_port", 0)
      protocol         = lookup(egress.value, "protocol", "-1")
    }
  }

  tags = merge(
    { "Name" = coalesce(var.default_security_group_name, var.name) },
    var.tags,
    var.default_security_group_tags,
    {
      Env       = "prod"
      yor_trace = "3cf38bff-134e-4d03-bf69-c0ec4b30317e"
  })
}

################################################################################
# DHCP Options Set
################################################################################

resource "aws_vpc_dhcp_options" "this" {
  count = local.create_vpc && var.enable_dhcp_options ? 1 : 0

  domain_name          = var.dhcp_options_domain_name
  domain_name_servers  = var.dhcp_options_domain_name_servers
  ntp_servers          = var.dhcp_options_ntp_servers
  netbios_name_servers = var.dhcp_options_netbios_name_servers
  netbios_node_type    = var.dhcp_options_netbios_node_type

  tags = merge(
    { "Name" = var.name },
    var.tags,
    var.dhcp_options_tags,
    {
      Env       = "prod"
      yor_trace = "ef739f4a-5594-4a2f-b8c4-fdedc9729e50"
  })
}

resource "aws_vpc_dhcp_options_association" "this" {
  count = local.create_vpc && var.enable_dhcp_options ? 1 : 0

  vpc_id          = local.vpc_id
  dhcp_options_id = aws_vpc_dhcp_options.this[0].id
}

################################################################################
# Internet Gateway
################################################################################

resource "aws_internet_gateway" "this" {
  count = local.create_vpc && var.create_igw && length(var.public_subnets) > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(
    { "Name" = var.name },
    var.tags,
    var.igw_tags,
    {
      Env       = "prod"
      yor_trace = "b18c8c35-d267-4cfa-ace9-0e70e9924d6a"
  })
}

resource "aws_egress_only_internet_gateway" "this" {
  count = local.create_vpc && var.create_egress_only_igw && var.enable_ipv6 && local.max_subnet_length > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(
    { "Name" = var.name },
    var.tags,
    var.igw_tags,
    {
      Env       = "prod"
      yor_trace = "25992ea7-e2db-41a8-8e0a-666408ae3826"
  })
}

################################################################################
# Default route
################################################################################

resource "aws_default_route_table" "default" {
  count = local.create_vpc && var.manage_default_route_table ? 1 : 0

  default_route_table_id = aws_vpc.this[0].default_route_table_id
  propagating_vgws       = var.default_route_table_propagating_vgws

  dynamic "route" {
    for_each = var.default_route_table_routes
    content {
      # One of the following destinations must be provided
      cidr_block      = route.value.cidr_block
      ipv6_cidr_block = lookup(route.value, "ipv6_cidr_block", null)

      # One of the following targets must be provided
      egress_only_gateway_id    = lookup(route.value, "egress_only_gateway_id", null)
      gateway_id                = lookup(route.value, "gateway_id", null)
      instance_id               = lookup(route.value, "instance_id", null)
      nat_gateway_id            = lookup(route.value, "nat_gateway_id", null)
      network_interface_id      = lookup(route.value, "network_interface_id", null)
      transit_gateway_id        = lookup(route.value, "transit_gateway_id", null)
      vpc_endpoint_id           = lookup(route.value, "vpc_endpoint_id", null)
      vpc_peering_connection_id = lookup(route.value, "vpc_peering_connection_id", null)
    }
  }

  timeouts {
    create = "5m"
    update = "5m"
  }

  tags = merge(
    { "Name" = coalesce(var.default_route_table_name, var.name) },
    var.tags,
    var.default_route_table_tags,
    {
      Env       = "prod"
      yor_trace = "c118a148-2684-41d6-b077-b2d0698cd5ad"
  })
}

################################################################################
# Publiс routes
################################################################################

resource "aws_route_table" "public" {
  count = local.create_vpc && length(var.public_subnets) > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(
    { "Name" = "${var.name}-${var.public_subnet_suffix}" },
    var.tags,
    var.public_route_table_tags,
    {
      Env       = "prod"
      yor_trace = "c81e19a0-27f3-4824-bdf8-712043e1e9cb"
  })
}

resource "aws_route" "public_internet_gateway" {
  count = local.create_vpc && var.create_igw && length(var.public_subnets) > 0 ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id

  timeouts {
    create = "5m"
  }
}

resource "aws_route" "public_internet_gateway_ipv6" {
  count = local.create_vpc && var.create_igw && var.enable_ipv6 && length(var.public_subnets) > 0 ? 1 : 0

  route_table_id              = aws_route_table.public[0].id
  destination_ipv6_cidr_block = "::/0"
  gateway_id                  = aws_internet_gateway.this[0].id
}

################################################################################
# Private routes
# There are as many routing tables as the number of NAT gateways
################################################################################

resource "aws_route_table" "private" {
  count = local.create_vpc && local.max_subnet_length > 0 ? local.nat_gateway_count : 0

  vpc_id = local.vpc_id

  tags = merge(
    {
      "Name" = var.single_nat_gateway ? "${var.name}-${var.private_subnet_suffix}" : format(
        "${var.name}-${var.private_subnet_suffix}-%s",
        element(var.azs, count.index),
      )
    },
    var.tags,
    var.private_route_table_tags,
    {
      Env       = "prod"
      yor_trace = "7f07fd52-e963-4e60-b9d3-311c991133af"
  })
}

################################################################################
# Database routes
################################################################################

resource "aws_route_table" "database" {
  count = local.create_vpc && var.create_database_subnet_route_table && length(var.database_subnets) > 0 ? var.single_nat_gateway || var.create_database_internet_gateway_route ? 1 : length(var.database_subnets) : 0

  vpc_id = local.vpc_id

  tags = merge(
    {
      "Name" = var.single_nat_gateway || var.create_database_internet_gateway_route ? "${var.name}-${var.database_subnet_suffix}" : format(
        "${var.name}-${var.database_subnet_suffix}-%s",
        element(var.azs, count.index),
      )
    },
    var.tags,
    var.database_route_table_tags,
    {
      Env       = "prod"
      yor_trace = "7984ce44-e304-4bcb-a791-af442b6c86fd"
  })
}

resource "aws_route" "database_internet_gateway" {
  count = local.create_vpc && var.create_igw && var.create_database_subnet_route_table && length(var.database_subnets) > 0 && var.create_database_internet_gateway_route && false == var.create_database_nat_gateway_route ? 1 : 0

  route_table_id         = aws_route_table.database[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id

  timeouts {
    create = "5m"
  }
}

resource "aws_route" "database_nat_gateway" {
  count = local.create_vpc && var.create_database_subnet_route_table && length(var.database_subnets) > 0 && false == var.create_database_internet_gateway_route && var.create_database_nat_gateway_route && var.enable_nat_gateway ? var.single_nat_gateway ? 1 : length(var.database_subnets) : 0

  route_table_id         = element(aws_route_table.database[*].id, count.index)
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = element(aws_nat_gateway.this[*].id, count.index)

  timeouts {
    create = "5m"
  }
}

resource "aws_route" "database_ipv6_egress" {
  count = local.create_vpc && var.create_egress_only_igw && var.enable_ipv6 && var.create_database_subnet_route_table && length(var.database_subnets) > 0 && var.create_database_internet_gateway_route ? 1 : 0

  route_table_id              = aws_route_table.database[0].id
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id      = aws_egress_only_internet_gateway.this[0].id

  timeouts {
    create = "5m"
  }
}

################################################################################
# Redshift routes
################################################################################

resource "aws_route_table" "redshift" {
  count = local.create_vpc && var.create_redshift_subnet_route_table && length(var.redshift_subnets) > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(
    { "Name" = "${var.name}-${var.redshift_subnet_suffix}" },
    var.tags,
    var.redshift_route_table_tags,
    {
      Env       = "prod"
      yor_trace = "ceb3976a-36a4-4985-9973-73ad876a000e"
  })
}

################################################################################
# Elasticache routes
################################################################################

resource "aws_route_table" "elasticache" {
  count = local.create_vpc && var.create_elasticache_subnet_route_table && length(var.elasticache_subnets) > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(
    { "Name" = "${var.name}-${var.elasticache_subnet_suffix}" },
    var.tags,
    var.elasticache_route_table_tags,
    {
      Env       = "prod"
      yor_trace = "67f3b9b5-1114-48ca-a712-802b7155bfb4"
  })
}

################################################################################
# Intra routes
################################################################################

resource "aws_route_table" "intra" {
  count = local.create_vpc && length(var.intra_subnets) > 0 ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(
    { "Name" = "${var.name}-${var.intra_subnet_suffix}" },
    var.tags,
    var.intra_route_table_tags,
    {
      Env       = "prod"
      yor_trace = "d3b2f478-892e-4d3c-a440-43e8d8ceef90"
  })
}

################################################################################
# Public subnet
################################################################################

resource "aws_subnet" "public" {
  count = local.create_vpc && length(var.public_subnets) > 0 && (false == var.one_nat_gateway_per_az || length(var.public_subnets) >= length(var.azs)) ? length(var.public_subnets) : 0

  vpc_id                          = local.vpc_id
  cidr_block                      = element(concat(var.public_subnets, [""]), count.index)
  availability_zone               = length(regexall("^[a-z]{2}-", element(var.azs, count.index))) > 0 ? element(var.azs, count.index) : null
  availability_zone_id            = length(regexall("^[a-z]{2}-", element(var.azs, count.index))) == 0 ? element(var.azs, count.index) : null
  map_public_ip_on_launch         = var.map_public_ip_on_launch
  assign_ipv6_address_on_creation = var.public_subnet_assign_ipv6_address_on_creation == null ? var.assign_ipv6_address_on_creation : var.public_subnet_assign_ipv6_address_on_creation

  ipv6_cidr_block = var.enable_ipv6 && length(var.public_subnet_ipv6_prefixes) > 0 ? cidrsubnet(aws_vpc.this[0].ipv6_cidr_block, 8, var.public_subnet_ipv6_prefixes[count.index]) : null

  tags = merge(
    {
      "Name" = format(
        "${var.name}-${var.public_subnet_suffix}-%s",
        element(var.azs, count.index),
      )
    },
    var.tags,
    var.public_subnet_tags,
    {
      Env       = "prod"
      yor_trace = "78c68a52-d57e-4632-a0bb-fb2c0dc724b6"
  })
}

################################################################################
# Private subnet
################################################################################

resource "aws_subnet" "private" {
  count = local.create_vpc && length(var.private_subnets) > 0 ? length(var.private_subnets) : 0

  vpc_id                          = local.vpc_id
  cidr_block                      = var.private_subnets[count.index]
  availability_zone               = length(regexall("^[a-z]{2}-", element(var.azs, count.index))) > 0 ? element(var.azs, count.index) : null
  availability_zone_id            = length(regexall("^[a-z]{2}-", element(var.azs, count.index))) == 0 ? element(var.azs, count.index) : null
  assign_ipv6_address_on_creation = var.private_subnet_assign_ipv6_address_on_creation == null ? var.assign_ipv6_address_on_creation : var.private_subnet_assign_ipv6_address_on_creation

  ipv6_cidr_block = var.enable_ipv6 && length(var.private_subnet_ipv6_prefixes) > 0 ? cidrsubnet(aws_vpc.this[0].ipv6_cidr_block, 8, var.private_subnet_ipv6_prefixes[count.index]) : null

  tags = merge(
    {
      "Name" = format(
        "${var.name}-${var.private_subnet_suffix}-%s",
        element(var.azs, count.index),
      )
    },
    var.tags,
    var.private_subnet_tags,
    {
      Env       = "prod"
      yor_trace = "fda4c94a-e62b-4b8f-8984-b028dda6b9d6"
  })
}

################################################################################
# Outpost subnet
################################################################################

resource "aws_subnet" "outpost" {
  count = local.create_vpc && length(var.outpost_subnets) > 0 ? length(var.outpost_subnets) : 0

  vpc_id                          = local.vpc_id
  cidr_block                      = var.outpost_subnets[count.index]
  availability_zone               = var.outpost_az
  assign_ipv6_address_on_creation = var.outpost_subnet_assign_ipv6_address_on_creation == null ? var.assign_ipv6_address_on_creation : var.outpost_subnet_assign_ipv6_address_on_creation

  ipv6_cidr_block = var.enable_ipv6 && length(var.outpost_subnet_ipv6_prefixes) > 0 ? cidrsubnet(aws_vpc.this[0].ipv6_cidr_block, 8, var.outpost_subnet_ipv6_prefixes[count.index]) : null

  outpost_arn = var.outpost_arn

  tags = merge(
    {
      "Name" = format(
        "${var.name}-${var.outpost_subnet_suffix}-%s",
        var.outpost_az,
      )
    },
    var.tags,
    var.outpost_subnet_tags,
    {
      Env       = "prod"
      yor_trace = "db9ba61b-5e38-45ce-bab7-59b5b698eba5"
  })
}

################################################################################
# Database subnet
################################################################################

resource "aws_subnet" "database" {
  count = local.create_vpc && length(var.database_subnets) > 0 ? length(var.database_subnets) : 0

  vpc_id                          = local.vpc_id
  cidr_block                      = var.database_subnets[count.index]
  availability_zone               = length(regexall("^[a-z]{2}-", element(var.azs, count.index))) > 0 ? element(var.azs, count.index) : null
  availability_zone_id            = length(regexall("^[a-z]{2}-", element(var.azs, count.index))) == 0 ? element(var.azs, count.index) : null
  assign_ipv6_address_on_creation = var.database_subnet_assign_ipv6_address_on_creation == null ? var.assign_ipv6_address_on_creation : var.database_subnet_assign_ipv6_address_on_creation

  ipv6_cidr_block = var.enable_ipv6 && length(var.database_subnet_ipv6_prefixes) > 0 ? cidrsubnet(aws_vpc.this[0].ipv6_cidr_block, 8, var.database_subnet_ipv6_prefixes[count.index]) : null

  tags = merge(
    {
      "Name" = format(
        "${var.name}-${var.database_subnet_suffix}-%s",
        element(var.azs, count.index),
      )
    },
    var.tags,
    var.database_subnet_tags,
    {
      Env       = "prod"
      yor_trace = "47635627-fe00-4ff3-9a26-780537143baa"
  })
}

resource "aws_db_subnet_group" "database" {
  count = local.create_vpc && length(var.database_subnets) > 0 && var.create_database_subnet_group ? 1 : 0

  name        = lower(coalesce(var.database_subnet_group_name, var.name))
  description = "Database subnet group for ${var.name}"
  subnet_ids  = aws_subnet.database[*].id

  tags = merge(
    {
      "Name" = lower(coalesce(var.database_subnet_group_name, var.name))
    },
    var.tags,
    var.database_subnet_group_tags,
    {
      Env       = "prod"
      yor_trace = "c9bd9a47-2387-4df9-98e4-b9803447f72c"
  })
}

################################################################################
# Redshift subnet
################################################################################

resource "aws_subnet" "redshift" {
  count = local.create_vpc && length(var.redshift_subnets) > 0 ? length(var.redshift_subnets) : 0

  vpc_id                          = local.vpc_id
  cidr_block                      = var.redshift_subnets[count.index]
  availability_zone               = length(regexall("^[a-z]{2}-", element(var.azs, count.index))) > 0 ? element(var.azs, count.index) : null
  availability_zone_id            = length(regexall("^[a-z]{2}-", element(var.azs, count.index))) == 0 ? element(var.azs, count.index) : null
  assign_ipv6_address_on_creation = var.redshift_subnet_assign_ipv6_address_on_creation == null ? var.assign_ipv6_address_on_creation : var.redshift_subnet_assign_ipv6_address_on_creation

  ipv6_cidr_block = var.enable_ipv6 && length(var.redshift_subnet_ipv6_prefixes) > 0 ? cidrsubnet(aws_vpc.this[0].ipv6_cidr_block, 8, var.redshift_subnet_ipv6_prefixes[count.index]) : null

  tags = merge(
    {
      "Name" = format(
        "${var.name}-${var.redshift_subnet_suffix}-%s",
        element(var.azs, count.index),
      )
    },
    var.tags,
    var.redshift_subnet_tags,
    {
      Env       = "prod"
      yor_trace = "d912c94f-8bbc-467a-88cb-0ddc6a85a5db"
  })
}

resource "aws_redshift_subnet_group" "redshift" {
  count = local.create_vpc && length(var.redshift_subnets) > 0 && var.create_redshift_subnet_group ? 1 : 0

  name        = lower(coalesce(var.redshift_subnet_group_name, var.name))
  description = "Redshift subnet group for ${var.name}"
  subnet_ids  = aws_subnet.redshift[*].id

  tags = merge(
    { "Name" = coalesce(var.redshift_subnet_group_name, var.name) },
    var.tags,
    var.redshift_subnet_group_tags,
    {
      Env       = "prod"
      yor_trace = "f8ccaeb8-0e00-4d18-8a40-024e3659f665"
  })
}

################################################################################
# ElastiCache subnet
################################################################################

resource "aws_subnet" "elasticache" {
  count = local.create_vpc && length(var.elasticache_subnets) > 0 ? length(var.elasticache_subnets) : 0

  vpc_id                          = local.vpc_id
  cidr_block                      = var.elasticache_subnets[count.index]
  availability_zone               = length(regexall("^[a-z]{2}-", element(var.azs, count.index))) > 0 ? element(var.azs, count.index) : null
  availability_zone_id            = length(regexall("^[a-z]{2}-", element(var.azs, count.index))) == 0 ? element(var.azs, count.index) : null
  assign_ipv6_address_on_creation = var.elasticache_subnet_assign_ipv6_address_on_creation == null ? var.assign_ipv6_address_on_creation : var.elasticache_subnet_assign_ipv6_address_on_creation

  ipv6_cidr_block = var.enable_ipv6 && length(var.elasticache_subnet_ipv6_prefixes) > 0 ? cidrsubnet(aws_vpc.this[0].ipv6_cidr_block, 8, var.elasticache_subnet_ipv6_prefixes[count.index]) : null

  tags = merge(
    {
      "Name" = format(
        "${var.name}-${var.elasticache_subnet_suffix}-%s",
        element(var.azs, count.index),
      )
    },
    var.tags,
    var.elasticache_subnet_tags,
    {
      Env       = "prod"
      yor_trace = "406357f2-9a63-4435-8a9e-b7fbb303a61a"
  })
}

resource "aws_elasticache_subnet_group" "elasticache" {
  count = local.create_vpc && length(var.elasticache_subnets) > 0 && var.create_elasticache_subnet_group ? 1 : 0

  name        = coalesce(var.elasticache_subnet_group_name, var.name)
  description = "ElastiCache subnet group for ${var.name}"
  subnet_ids  = aws_subnet.elasticache[*].id

  tags = merge(
    { "Name" = coalesce(var.elasticache_subnet_group_name, var.name) },
    var.tags,
    var.elasticache_subnet_group_tags,
    {
      Env       = "prod"
      yor_trace = "6fc413b0-cd02-44c3-aa35-ad7759719735"
  })
}

################################################################################
# Intra subnets - private subnet without NAT gateway
################################################################################

resource "aws_subnet" "intra" {
  count = local.create_vpc && length(var.intra_subnets) > 0 ? length(var.intra_subnets) : 0

  vpc_id                          = local.vpc_id
  cidr_block                      = var.intra_subnets[count.index]
  availability_zone               = length(regexall("^[a-z]{2}-", element(var.azs, count.index))) > 0 ? element(var.azs, count.index) : null
  availability_zone_id            = length(regexall("^[a-z]{2}-", element(var.azs, count.index))) == 0 ? element(var.azs, count.index) : null
  assign_ipv6_address_on_creation = var.intra_subnet_assign_ipv6_address_on_creation == null ? var.assign_ipv6_address_on_creation : var.intra_subnet_assign_ipv6_address_on_creation

  ipv6_cidr_block = var.enable_ipv6 && length(var.intra_subnet_ipv6_prefixes) > 0 ? cidrsubnet(aws_vpc.this[0].ipv6_cidr_block, 8, var.intra_subnet_ipv6_prefixes[count.index]) : null

  tags = merge(
    {
      "Name" = format(
        "${var.name}-${var.intra_subnet_suffix}-%s",
        element(var.azs, count.index),
      )
    },
    var.tags,
    var.intra_subnet_tags,
    {
      Env       = "prod"
      yor_trace = "db81d2ce-4dfd-43dd-8eaf-6d9a660877f6"
  })
}

################################################################################
# Default Network ACLs
################################################################################

resource "aws_default_network_acl" "this" {
  count = local.create_vpc && var.manage_default_network_acl ? 1 : 0

  default_network_acl_id = aws_vpc.this[0].default_network_acl_id

  # subnet_ids is using lifecycle ignore_changes, so it is not necessary to list
  # any explicitly. See https://github.com/terraform-aws-modules/terraform-aws-vpc/issues/736.
  subnet_ids = null

  dynamic "ingress" {
    for_each = var.default_network_acl_ingress
    content {
      action          = ingress.value.action
      cidr_block      = lookup(ingress.value, "cidr_block", null)
      from_port       = ingress.value.from_port
      icmp_code       = lookup(ingress.value, "icmp_code", null)
      icmp_type       = lookup(ingress.value, "icmp_type", null)
      ipv6_cidr_block = lookup(ingress.value, "ipv6_cidr_block", null)
      protocol        = ingress.value.protocol
      rule_no         = ingress.value.rule_no
      to_port         = ingress.value.to_port
    }
  }
  dynamic "egress" {
    for_each = var.default_network_acl_egress
    content {
      action          = egress.value.action
      cidr_block      = lookup(egress.value, "cidr_block", null)
      from_port       = egress.value.from_port
      icmp_code       = lookup(egress.value, "icmp_code", null)
      icmp_type       = lookup(egress.value, "icmp_type", null)
      ipv6_cidr_block = lookup(egress.value, "ipv6_cidr_block", null)
      protocol        = egress.value.protocol
      rule_no         = egress.value.rule_no
      to_port         = egress.value.to_port
    }
  }

  tags = merge(
    { "Name" = coalesce(var.default_network_acl_name, var.name) },
    var.tags,
    var.default_network_acl_tags,
    {
      Env       = "prod"
      yor_trace = "8d65ab9b-bbed-4fea-a384-778b65a8b31b"
  })

  lifecycle {
    ignore_changes = [subnet_ids]
  }
}

################################################################################
# Public Network ACLs
################################################################################

resource "aws_network_acl" "public" {
  count = local.create_vpc && var.public_dedicated_network_acl && length(var.public_subnets) > 0 ? 1 : 0

  vpc_id     = local.vpc_id
  subnet_ids = aws_subnet.public[*].id

  tags = merge(
    { "Name" = "${var.name}-${var.public_subnet_suffix}" },
    var.tags,
    var.public_acl_tags,
    {
      Env       = "prod"
      yor_trace = "572d52a9-4843-4ebe-a6ce-3ac34b77ffe6"
  })
}

resource "aws_network_acl_rule" "public_inbound" {
  count = local.create_vpc && var.public_dedicated_network_acl && length(var.public_subnets) > 0 ? length(var.public_inbound_acl_rules) : 0

  network_acl_id = aws_network_acl.public[0].id

  egress          = false
  rule_number     = var.public_inbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.public_inbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.public_inbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.public_inbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.public_inbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.public_inbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.public_inbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.public_inbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.public_inbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

resource "aws_network_acl_rule" "public_outbound" {
  count = local.create_vpc && var.public_dedicated_network_acl && length(var.public_subnets) > 0 ? length(var.public_outbound_acl_rules) : 0

  network_acl_id = aws_network_acl.public[0].id

  egress          = true
  rule_number     = var.public_outbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.public_outbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.public_outbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.public_outbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.public_outbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.public_outbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.public_outbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.public_outbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.public_outbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

################################################################################
# Private Network ACLs
################################################################################

resource "aws_network_acl" "private" {
  count = local.create_vpc && var.private_dedicated_network_acl && length(var.private_subnets) > 0 ? 1 : 0

  vpc_id     = local.vpc_id
  subnet_ids = aws_subnet.private[*].id

  tags = merge(
    { "Name" = "${var.name}-${var.private_subnet_suffix}" },
    var.tags,
    var.private_acl_tags,
    {
      Env       = "prod"
      yor_trace = "fbd8f14f-e585-4fa2-bbb1-e0e451332c99"
  })
}

resource "aws_network_acl_rule" "private_inbound" {
  count = local.create_vpc && var.private_dedicated_network_acl && length(var.private_subnets) > 0 ? length(var.private_inbound_acl_rules) : 0

  network_acl_id = aws_network_acl.private[0].id

  egress          = false
  rule_number     = var.private_inbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.private_inbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.private_inbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.private_inbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.private_inbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.private_inbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.private_inbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.private_inbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.private_inbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

resource "aws_network_acl_rule" "private_outbound" {
  count = local.create_vpc && var.private_dedicated_network_acl && length(var.private_subnets) > 0 ? length(var.private_outbound_acl_rules) : 0

  network_acl_id = aws_network_acl.private[0].id

  egress          = true
  rule_number     = var.private_outbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.private_outbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.private_outbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.private_outbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.private_outbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.private_outbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.private_outbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.private_outbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.private_outbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

################################################################################
# Outpost Network ACLs
################################################################################

resource "aws_network_acl" "outpost" {
  count = local.create_vpc && var.outpost_dedicated_network_acl && length(var.outpost_subnets) > 0 ? 1 : 0

  vpc_id     = local.vpc_id
  subnet_ids = aws_subnet.outpost[*].id

  tags = merge(
    { "Name" = "${var.name}-${var.outpost_subnet_suffix}" },
    var.tags,
    var.outpost_acl_tags,
    {
      Env       = "prod"
      yor_trace = "2fadb0db-e0f1-4794-a438-3e2fea92c4c8"
  })
}

resource "aws_network_acl_rule" "outpost_inbound" {
  count = local.create_vpc && var.outpost_dedicated_network_acl && length(var.outpost_subnets) > 0 ? length(var.outpost_inbound_acl_rules) : 0

  network_acl_id = aws_network_acl.outpost[0].id

  egress          = false
  rule_number     = var.outpost_inbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.outpost_inbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.outpost_inbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.outpost_inbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.outpost_inbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.outpost_inbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.outpost_inbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.outpost_inbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.outpost_inbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

resource "aws_network_acl_rule" "outpost_outbound" {
  count = local.create_vpc && var.outpost_dedicated_network_acl && length(var.outpost_subnets) > 0 ? length(var.outpost_outbound_acl_rules) : 0

  network_acl_id = aws_network_acl.outpost[0].id

  egress          = true
  rule_number     = var.outpost_outbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.outpost_outbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.outpost_outbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.outpost_outbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.outpost_outbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.outpost_outbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.outpost_outbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.outpost_outbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.outpost_outbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

################################################################################
# Intra Network ACLs
################################################################################

resource "aws_network_acl" "intra" {
  count = local.create_vpc && var.intra_dedicated_network_acl && length(var.intra_subnets) > 0 ? 1 : 0

  vpc_id     = local.vpc_id
  subnet_ids = aws_subnet.intra[*].id

  tags = merge(
    { "Name" = "${var.name}-${var.intra_subnet_suffix}" },
    var.tags,
    var.intra_acl_tags,
    {
      Env       = "prod"
      yor_trace = "aef94eb8-396d-48ea-a7bb-fc4f0c5d9b94"
  })
}

resource "aws_network_acl_rule" "intra_inbound" {
  count = local.create_vpc && var.intra_dedicated_network_acl && length(var.intra_subnets) > 0 ? length(var.intra_inbound_acl_rules) : 0

  network_acl_id = aws_network_acl.intra[0].id

  egress          = false
  rule_number     = var.intra_inbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.intra_inbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.intra_inbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.intra_inbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.intra_inbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.intra_inbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.intra_inbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.intra_inbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.intra_inbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

resource "aws_network_acl_rule" "intra_outbound" {
  count = local.create_vpc && var.intra_dedicated_network_acl && length(var.intra_subnets) > 0 ? length(var.intra_outbound_acl_rules) : 0

  network_acl_id = aws_network_acl.intra[0].id

  egress          = true
  rule_number     = var.intra_outbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.intra_outbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.intra_outbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.intra_outbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.intra_outbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.intra_outbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.intra_outbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.intra_outbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.intra_outbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

################################################################################
# Database Network ACLs
################################################################################

resource "aws_network_acl" "database" {
  count = local.create_vpc && var.database_dedicated_network_acl && length(var.database_subnets) > 0 ? 1 : 0

  vpc_id     = local.vpc_id
  subnet_ids = aws_subnet.database[*].id

  tags = merge(
    { "Name" = "${var.name}-${var.database_subnet_suffix}" },
    var.tags,
    var.database_acl_tags,
    {
      Env       = "prod"
      yor_trace = "ace9a4a3-89bb-478d-a378-0b8ae6926aee"
  })
}

resource "aws_network_acl_rule" "database_inbound" {
  count = local.create_vpc && var.database_dedicated_network_acl && length(var.database_subnets) > 0 ? length(var.database_inbound_acl_rules) : 0

  network_acl_id = aws_network_acl.database[0].id

  egress          = false
  rule_number     = var.database_inbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.database_inbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.database_inbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.database_inbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.database_inbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.database_inbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.database_inbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.database_inbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.database_inbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

resource "aws_network_acl_rule" "database_outbound" {
  count = local.create_vpc && var.database_dedicated_network_acl && length(var.database_subnets) > 0 ? length(var.database_outbound_acl_rules) : 0

  network_acl_id = aws_network_acl.database[0].id

  egress          = true
  rule_number     = var.database_outbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.database_outbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.database_outbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.database_outbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.database_outbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.database_outbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.database_outbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.database_outbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.database_outbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

################################################################################
# Redshift Network ACLs
################################################################################

resource "aws_network_acl" "redshift" {
  count = local.create_vpc && var.redshift_dedicated_network_acl && length(var.redshift_subnets) > 0 ? 1 : 0

  vpc_id     = local.vpc_id
  subnet_ids = aws_subnet.redshift[*].id

  tags = merge(
    { "Name" = "${var.name}-${var.redshift_subnet_suffix}" },
    var.tags,
    var.redshift_acl_tags,
    {
      Env       = "prod"
      yor_trace = "f22069f7-2775-40d6-951a-4a071e6400f6"
  })
}

resource "aws_network_acl_rule" "redshift_inbound" {
  count = local.create_vpc && var.redshift_dedicated_network_acl && length(var.redshift_subnets) > 0 ? length(var.redshift_inbound_acl_rules) : 0

  network_acl_id = aws_network_acl.redshift[0].id

  egress          = false
  rule_number     = var.redshift_inbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.redshift_inbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.redshift_inbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.redshift_inbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.redshift_inbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.redshift_inbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.redshift_inbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.redshift_inbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.redshift_inbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

resource "aws_network_acl_rule" "redshift_outbound" {
  count = local.create_vpc && var.redshift_dedicated_network_acl && length(var.redshift_subnets) > 0 ? length(var.redshift_outbound_acl_rules) : 0

  network_acl_id = aws_network_acl.redshift[0].id

  egress          = true
  rule_number     = var.redshift_outbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.redshift_outbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.redshift_outbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.redshift_outbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.redshift_outbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.redshift_outbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.redshift_outbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.redshift_outbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.redshift_outbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

################################################################################
# Elasticache Network ACLs
################################################################################

resource "aws_network_acl" "elasticache" {
  count = local.create_vpc && var.elasticache_dedicated_network_acl && length(var.elasticache_subnets) > 0 ? 1 : 0

  vpc_id     = local.vpc_id
  subnet_ids = aws_subnet.elasticache[*].id

  tags = merge(
    { "Name" = "${var.name}-${var.elasticache_subnet_suffix}" },
    var.tags,
    var.elasticache_acl_tags,
    {
      Env       = "prod"
      yor_trace = "0859ed61-0fcf-420a-9bd8-607fd8d3b029"
  })
}

resource "aws_network_acl_rule" "elasticache_inbound" {
  count = local.create_vpc && var.elasticache_dedicated_network_acl && length(var.elasticache_subnets) > 0 ? length(var.elasticache_inbound_acl_rules) : 0

  network_acl_id = aws_network_acl.elasticache[0].id

  egress          = false
  rule_number     = var.elasticache_inbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.elasticache_inbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.elasticache_inbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.elasticache_inbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.elasticache_inbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.elasticache_inbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.elasticache_inbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.elasticache_inbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.elasticache_inbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

resource "aws_network_acl_rule" "elasticache_outbound" {
  count = local.create_vpc && var.elasticache_dedicated_network_acl && length(var.elasticache_subnets) > 0 ? length(var.elasticache_outbound_acl_rules) : 0

  network_acl_id = aws_network_acl.elasticache[0].id

  egress          = true
  rule_number     = var.elasticache_outbound_acl_rules[count.index]["rule_number"]
  rule_action     = var.elasticache_outbound_acl_rules[count.index]["rule_action"]
  from_port       = lookup(var.elasticache_outbound_acl_rules[count.index], "from_port", null)
  to_port         = lookup(var.elasticache_outbound_acl_rules[count.index], "to_port", null)
  icmp_code       = lookup(var.elasticache_outbound_acl_rules[count.index], "icmp_code", null)
  icmp_type       = lookup(var.elasticache_outbound_acl_rules[count.index], "icmp_type", null)
  protocol        = var.elasticache_outbound_acl_rules[count.index]["protocol"]
  cidr_block      = lookup(var.elasticache_outbound_acl_rules[count.index], "cidr_block", null)
  ipv6_cidr_block = lookup(var.elasticache_outbound_acl_rules[count.index], "ipv6_cidr_block", null)
}

################################################################################
# NAT Gateway
################################################################################

locals {
  nat_gateway_ips = var.reuse_nat_ips ? var.external_nat_ip_ids : try(aws_eip.nat[*].id, [])
}

resource "aws_eip" "nat" {
  count = local.create_vpc && var.enable_nat_gateway && false == var.reuse_nat_ips ? local.nat_gateway_count : 0

  vpc = true

  tags = merge(
    {
      "Name" = format(
        "${var.name}-%s",
        element(var.azs, var.single_nat_gateway ? 0 : count.index),
      )
    },
    var.tags,
    var.nat_eip_tags,
    {
      Env       = "prod"
      yor_trace = "5a7614b0-715b-46a1-b914-cf6b5d1b9df8"
  })
}

resource "aws_nat_gateway" "this" {
  count = local.create_vpc && var.enable_nat_gateway ? local.nat_gateway_count : 0

  allocation_id = element(
    local.nat_gateway_ips,
    var.single_nat_gateway ? 0 : count.index,
  )
  subnet_id = element(
    aws_subnet.public[*].id,
    var.single_nat_gateway ? 0 : count.index,
  )

  tags = merge(
    {
      "Name" = format(
        "${var.name}-%s",
        element(var.azs, var.single_nat_gateway ? 0 : count.index),
      )
    },
    var.tags,
    var.nat_gateway_tags,
    {
      Env       = "prod"
      yor_trace = "d42a8199-ab14-4197-991c-ca8e01efadd1"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route" "private_nat_gateway" {
  count = local.create_vpc && var.enable_nat_gateway ? local.nat_gateway_count : 0

  route_table_id         = element(aws_route_table.private[*].id, count.index)
  destination_cidr_block = var.nat_gateway_destination_cidr_block
  nat_gateway_id         = element(aws_nat_gateway.this[*].id, count.index)

  timeouts {
    create = "5m"
  }
}

resource "aws_route" "private_ipv6_egress" {
  count = local.create_vpc && var.create_egress_only_igw && var.enable_ipv6 ? length(var.private_subnets) : 0

  route_table_id              = element(aws_route_table.private[*].id, count.index)
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id      = element(aws_egress_only_internet_gateway.this[*].id, 0)
}

################################################################################
# Route table association
################################################################################

resource "aws_route_table_association" "private" {
  count = local.create_vpc && length(var.private_subnets) > 0 ? length(var.private_subnets) : 0

  subnet_id = element(aws_subnet.private[*].id, count.index)
  route_table_id = element(
    aws_route_table.private[*].id,
    var.single_nat_gateway ? 0 : count.index,
  )
}

resource "aws_route_table_association" "outpost" {
  count = local.create_vpc && length(var.outpost_subnets) > 0 ? length(var.outpost_subnets) : 0

  subnet_id = element(aws_subnet.outpost[*].id, count.index)
  route_table_id = element(
    aws_route_table.private[*].id,
    var.single_nat_gateway ? 0 : count.index,
  )
}

resource "aws_route_table_association" "database" {
  count = local.create_vpc && length(var.database_subnets) > 0 ? length(var.database_subnets) : 0

  subnet_id = element(aws_subnet.database[*].id, count.index)
  route_table_id = element(
    coalescelist(aws_route_table.database[*].id, aws_route_table.private[*].id),
    var.create_database_subnet_route_table ? var.single_nat_gateway || var.create_database_internet_gateway_route ? 0 : count.index : count.index,
  )
}

resource "aws_route_table_association" "redshift" {
  count = local.create_vpc && length(var.redshift_subnets) > 0 && false == var.enable_public_redshift ? length(var.redshift_subnets) : 0

  subnet_id = element(aws_subnet.redshift[*].id, count.index)
  route_table_id = element(
    coalescelist(aws_route_table.redshift[*].id, aws_route_table.private[*].id),
    var.single_nat_gateway || var.create_redshift_subnet_route_table ? 0 : count.index,
  )
}

resource "aws_route_table_association" "redshift_public" {
  count = local.create_vpc && length(var.redshift_subnets) > 0 && var.enable_public_redshift ? length(var.redshift_subnets) : 0

  subnet_id = element(aws_subnet.redshift[*].id, count.index)
  route_table_id = element(
    coalescelist(aws_route_table.redshift[*].id, aws_route_table.public[*].id),
    var.single_nat_gateway || var.create_redshift_subnet_route_table ? 0 : count.index,
  )
}

resource "aws_route_table_association" "elasticache" {
  count = local.create_vpc && length(var.elasticache_subnets) > 0 ? length(var.elasticache_subnets) : 0

  subnet_id = element(aws_subnet.elasticache[*].id, count.index)
  route_table_id = element(
    coalescelist(
      aws_route_table.elasticache[*].id,
      aws_route_table.private[*].id,
    ),
    var.single_nat_gateway || var.create_elasticache_subnet_route_table ? 0 : count.index,
  )
}

resource "aws_route_table_association" "intra" {
  count = local.create_vpc && length(var.intra_subnets) > 0 ? length(var.intra_subnets) : 0

  subnet_id      = element(aws_subnet.intra[*].id, count.index)
  route_table_id = element(aws_route_table.intra[*].id, 0)
}

resource "aws_route_table_association" "public" {
  count = local.create_vpc && length(var.public_subnets) > 0 ? length(var.public_subnets) : 0

  subnet_id      = element(aws_subnet.public[*].id, count.index)
  route_table_id = aws_route_table.public[0].id
}

################################################################################
# Customer Gateways
################################################################################

resource "aws_customer_gateway" "this" {
  for_each = var.customer_gateways

  bgp_asn     = each.value["bgp_asn"]
  ip_address  = each.value["ip_address"]
  device_name = lookup(each.value, "device_name", null)
  type        = "ipsec.1"

  tags = merge(
    { Name = "${var.name}-${each.key}" },
    var.tags,
    var.customer_gateway_tags,
    {
      Env       = "prod"
      yor_trace = "6a203a10-a1f3-41e4-bcba-1f323ec8dfd2"
  })
}

################################################################################
# VPN Gateway
################################################################################

resource "aws_vpn_gateway" "this" {
  count = local.create_vpc && var.enable_vpn_gateway ? 1 : 0

  vpc_id            = local.vpc_id
  amazon_side_asn   = var.amazon_side_asn
  availability_zone = var.vpn_gateway_az

  tags = merge(
    { "Name" = var.name },
    var.tags,
    var.vpn_gateway_tags,
    {
      Env       = "prod"
      yor_trace = "235c8ecd-1de2-40ba-a15a-f5ae34ea9460"
  })
}

resource "aws_vpn_gateway_attachment" "this" {
  count = var.vpn_gateway_id != "" ? 1 : 0

  vpc_id         = local.vpc_id
  vpn_gateway_id = var.vpn_gateway_id
}

resource "aws_vpn_gateway_route_propagation" "public" {
  count = local.create_vpc && var.propagate_public_route_tables_vgw && (var.enable_vpn_gateway || var.vpn_gateway_id != "") ? 1 : 0

  route_table_id = element(aws_route_table.public[*].id, count.index)
  vpn_gateway_id = element(
    concat(
      aws_vpn_gateway.this[*].id,
      aws_vpn_gateway_attachment.this[*].vpn_gateway_id,
    ),
    count.index,
  )
}

resource "aws_vpn_gateway_route_propagation" "private" {
  count = local.create_vpc && var.propagate_private_route_tables_vgw && (var.enable_vpn_gateway || var.vpn_gateway_id != "") ? length(var.private_subnets) : 0

  route_table_id = element(aws_route_table.private[*].id, count.index)
  vpn_gateway_id = element(
    concat(
      aws_vpn_gateway.this[*].id,
      aws_vpn_gateway_attachment.this[*].vpn_gateway_id,
    ),
    count.index,
  )
}

resource "aws_vpn_gateway_route_propagation" "intra" {
  count = local.create_vpc && var.propagate_intra_route_tables_vgw && (var.enable_vpn_gateway || var.vpn_gateway_id != "") ? length(var.intra_subnets) : 0

  route_table_id = element(aws_route_table.intra[*].id, count.index)
  vpn_gateway_id = element(
    concat(
      aws_vpn_gateway.this[*].id,
      aws_vpn_gateway_attachment.this[*].vpn_gateway_id,
    ),
    count.index,
  )
}

################################################################################
# Defaults
################################################################################

resource "aws_default_vpc" "this" {
  count = var.manage_default_vpc ? 1 : 0

  enable_dns_support   = var.default_vpc_enable_dns_support
  enable_dns_hostnames = var.default_vpc_enable_dns_hostnames
  enable_classiclink   = null # https://github.com/hashicorp/terraform/issues/31730

  tags = merge(
    { "Name" = coalesce(var.default_vpc_name, "default") },
    var.tags,
    var.default_vpc_tags,
    {
      Env       = "prod"
      yor_trace = "1f72265f-5f2c-41f8-99cc-e873ee9ebed5"
  })
}
