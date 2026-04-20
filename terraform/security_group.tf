# ── K8s Cluster Security Group ───────────────────────────────────────────────
resource "aws_security_group" "k8s_cluster" {
  name        = "${var.project_name}-k8s-cluster"
  description = "Security group for VoteVibe K8s cluster (master + workers)"
  vpc_id      = local.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-k8s-cluster"
  })
}

# SSH from your IP only
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.k8s_cluster.id
  description       = "SSH from operator IP"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = var.your_ip
}

# Kubernetes API server — open so kubectl works from outside the cluster
resource "aws_vpc_security_group_ingress_rule" "k8s_api" {
  security_group_id = aws_security_group.k8s_cluster.id
  description       = "Kubernetes API server"
  from_port         = 6443
  to_port           = 6443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# etcd (inter-node only — RFC-1918 range covers EC2 private IPs)
resource "aws_vpc_security_group_ingress_rule" "etcd" {
  security_group_id = aws_security_group.k8s_cluster.id
  description       = "etcd peer communication"
  from_port         = 2379
  to_port           = 2380
  ip_protocol       = "tcp"
  cidr_ipv4         = "10.0.0.0/8"
}

# Kubelet / kube-controller-manager / kube-scheduler (inter-node only)
resource "aws_vpc_security_group_ingress_rule" "kubelet" {
  security_group_id = aws_security_group.k8s_cluster.id
  description       = "Kubelet, controller-manager, scheduler"
  from_port         = 10250
  to_port           = 10252
  ip_protocol       = "tcp"
  cidr_ipv4         = "10.0.0.0/8"
}

# NodePort range for VoteVibe services (30001 Blue, 30002 Red, 30003 Scoreboard)
resource "aws_vpc_security_group_ingress_rule" "nodeport" {
  security_group_id = aws_security_group.k8s_cluster.id
  description       = "NodePort services (VoteVibe ports 30001-30003)"
  from_port         = 30001
  to_port           = 30003
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"
}

# All traffic between nodes in the same security group (pod networking, flannel, etc.)
resource "aws_vpc_security_group_ingress_rule" "inter_node" {
  security_group_id            = aws_security_group.k8s_cluster.id
  description                  = "Unrestricted inter-node traffic (flannel overlay + DNS)"
  from_port                    = -1
  to_port                      = -1
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.k8s_cluster.id
}

# All outbound traffic
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.k8s_cluster.id
  description       = "All outbound traffic"
  from_port         = -1
  to_port           = -1
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
