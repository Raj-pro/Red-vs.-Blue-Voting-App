variable "aws_region" {
  description = "AWS region to deploy the cluster"
  type        = string
  default     = "us-east-1"
}

variable "key_name" {
  description = "Name of the existing EC2 key pair for SSH access"
  type        = string
}

variable "your_ip" {
  description = "Your public IP in CIDR notation (e.g. 203.0.113.5/32) for SSH access"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for all K8s nodes"
  type        = string
  default     = "t3.medium"
}

variable "project_name" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "votevibe"
}

variable "vpc_id" {
  description = "VPC ID to launch instances into. Leave empty to use the default VPC."
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Subnet ID to launch instances into. Leave empty to auto-select from the VPC."
  type        = string
  default     = ""
}
