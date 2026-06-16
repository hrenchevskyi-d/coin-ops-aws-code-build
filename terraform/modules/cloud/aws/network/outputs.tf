output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "subnet_ids" {
  value = { for name, subnet in aws_subnet.subnet : name => subnet.id }
}

output "private_subnet_ids" {
  description = "Subnet IDs for subnets without public = true (used by aws_nat_route)."
  value       = { for name, subnet in aws_subnet.subnet : name => subnet.id if contains(keys(local.private_subnets), name) }
}

output "public_subnet_ids" {
  description = "Subnet IDs for subnets with public = true."
  value       = { for name, subnet in aws_subnet.subnet : name => subnet.id if contains(keys(local.public_subnets), name) }
}

output "database_subnet_ids" {
  description = "Private subnet IDs used by managed database subnet groups."
  value       = [for name, subnet in aws_subnet.subnet : subnet.id if contains(keys(local.private_subnets), name)]
}

output "private_route_table_id" {
  description = "ID of the private route table (owned by aws_network). Pass to aws_nat_route."
  value       = aws_route_table.private.id
}

output "public_route_table_id" {
  description = "ID of the public route table (owned by aws_network). Pass to aws_nat_route for remote cloud routes on public workloads."
  value       = aws_route_table.public.id
}

output "managed_nat_gateway_id" {
  description = "AWS managed NAT Gateway ID when enabled."
  value       = try(aws_nat_gateway.this[0].id, "")
}

output "managed_nat_gateway_public_ip" {
  description = "Public IP address of the AWS managed NAT Gateway when enabled."
  value       = try(aws_eip.nat[0].public_ip, "")
}
