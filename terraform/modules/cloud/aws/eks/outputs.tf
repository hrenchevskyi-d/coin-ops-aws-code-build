output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_ca_certificate" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  value = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "node_group_name" {
  value = aws_eks_node_group.system.node_group_name
}

output "node_role_name" {
  value = aws_iam_role.node.name
}

output "node_group_autoscaling_group_names" {
  value = try([for group in aws_eks_node_group.system.resources[0].autoscaling_groups : group.name], [])
}

output "oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.this.arn
}

output "ebs_csi_role_arn" {
  value = aws_iam_role.ebs_csi.arn
}
