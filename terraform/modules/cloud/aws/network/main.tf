# AWS network keeps public and private route tables separate. Extra routes
# are attached later by nat_route so base VPC creation remains simple.
locals {
  fallback_subnets = {
    internal = { cidr = "10.10.1.0/24" }
    external = { cidr = "10.10.2.0/24", public = true }
  }
  subnets = length(var.subnets) > 0 ? var.subnets : local.fallback_subnets
  # public=true is the only flag that receives Internet Gateway routing here.
  public_subnets  = { for name, cfg in local.subnets : name => cfg if lookup(cfg, "public", false) }
  private_subnets = { for name, cfg in local.subnets : name => cfg if !lookup(cfg, "public", false) }

  managed_nat_gateway_enabled       = try(var.managed_nat_gateway.enabled, false)
  managed_nat_gateway_public_subnet = try(var.managed_nat_gateway.public_subnet, "")
}

resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr
  tags       = { Name = var.vpc_name }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags   = { Name = "${var.vpc_name}-igw" }
}

resource "aws_subnet" "subnet" {
  for_each = local.subnets

  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = each.value.cidr
  availability_zone       = lookup(var.zones, lookup(each.value, "availability_zone_key", "primary"), var.zone)
  map_public_ip_on_launch = lookup(each.value, "public", false)

  tags = { Name = "${each.key}-subnet" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${var.vpc_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  for_each       = local.public_subnets
  subnet_id      = aws_subnet.subnet[each.key].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.vpc.id
  tags   = { Name = "${var.vpc_name}-private-rt" }
}

resource "aws_route_table_association" "private" {
  for_each       = local.private_subnets
  subnet_id      = aws_subnet.subnet[each.key].id
  route_table_id = aws_route_table.private.id
}

resource "aws_eip" "nat" {
  count  = local.managed_nat_gateway_enabled ? 1 : 0
  domain = "vpc"

  tags = { Name = "${var.vpc_name}-nat-eip" }
}

resource "aws_nat_gateway" "this" {
  count = local.managed_nat_gateway_enabled ? 1 : 0

  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.subnet[local.managed_nat_gateway_public_subnet].id

  tags = { Name = "${var.vpc_name}-nat-gateway" }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route" "private_default_via_managed_nat" {
  count = local.managed_nat_gateway_enabled ? 1 : 0

  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}
