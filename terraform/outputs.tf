output "master_public_ip" {
  description = "Public IP of the Kubernetes master node"
  value       = aws_instance.master.public_ip
}

output "master_private_ip" {
  description = "Private IP of the Kubernetes master node"
  value       = aws_instance.master.private_ip
}

output "worker_01_public_ip" {
  description = "Public IP of worker node 01"
  value       = aws_instance.worker_01.public_ip
}

output "worker_01_private_ip" {
  description = "Private IP of worker node 01"
  value       = aws_instance.worker_01.private_ip
}

output "worker_02_public_ip" {
  description = "Public IP of worker node 02"
  value       = aws_instance.worker_02.public_ip
}

output "worker_02_private_ip" {
  description = "Private IP of worker node 02"
  value       = aws_instance.worker_02.private_ip
}

output "ssh_master" {
  description = "SSH command for the master node"
  value       = "ssh -i <your-key>.pem ubuntu@${aws_instance.master.public_ip}"
}

output "ssh_worker_01" {
  description = "SSH command for worker node 01"
  value       = "ssh -i <your-key>.pem ubuntu@${aws_instance.worker_01.public_ip}"
}

output "ssh_worker_02" {
  description = "SSH command for worker node 02"
  value       = "ssh -i <your-key>.pem ubuntu@${aws_instance.worker_02.public_ip}"
}

output "votevibe_urls" {
  description = "VoteVibe app URLs (available once K8s cluster is up)"
  value = {
    blue_team  = "http://${aws_instance.master.public_ip}:30001"
    red_team   = "http://${aws_instance.master.public_ip}:30002"
    scoreboard = "http://${aws_instance.master.public_ip}:30003"
  }
}

output "scp_yaml_command" {
  description = "SCP command to transfer YAML manifests to master node"
  value       = "scp -i <your-key>.pem ../*.yaml ubuntu@${aws_instance.master.public_ip}:~/votevibe/"
}

output "get_join_command" {
  description = "After setup: retrieve the kubeadm join command from the master"
  value       = "ssh -i <your-key>.pem ubuntu@${aws_instance.master.public_ip} 'cat ~/join-command.txt'"
}

output "security_group_id" {
  description = "ID of the K8s cluster security group"
  value       = aws_security_group.k8s_cluster.id
}

output "ami_id" {
  description = "Ubuntu 22.04 AMI used for all nodes"
  value       = data.aws_ami.ubuntu_22_04.id
}
