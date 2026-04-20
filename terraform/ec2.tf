# ── EC2 Instances ─────────────────────────────────────────────────────────────
# Scripts are base64-encoded to safely embed heredoc-heavy bash into user_data.
locals {
  common_b64 = base64encode(file("${path.module}/user_data/common.sh"))
  master_b64 = base64encode(file("${path.module}/user_data/master.sh"))
  worker_b64 = base64encode(file("${path.module}/user_data/worker.sh"))
}

# ── Master Node ───────────────────────────────────────────────────────────────
resource "aws_instance" "master" {
  ami                         = data.aws_ami.ubuntu_22_04.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [aws_security_group.k8s_cluster.id]
  associate_public_ip_address = true

  user_data = <<-USERDATA
    #!/bin/bash
    echo "${local.common_b64}" | base64 -d > /tmp/common.sh
    echo "${local.master_b64}" | base64 -d > /tmp/master.sh
    chmod +x /tmp/common.sh /tmp/master.sh
    bash /tmp/master.sh
  USERDATA

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
  }

  tags = merge(local.common_tags, {
    Name = "k8s-master"
    Role = "control-plane"
  })
}

# ── Worker Node 01 ────────────────────────────────────────────────────────────
resource "aws_instance" "worker_01" {
  ami                         = data.aws_ami.ubuntu_22_04.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [aws_security_group.k8s_cluster.id]
  associate_public_ip_address = true

  user_data = <<-USERDATA
    #!/bin/bash
    echo "${local.common_b64}" | base64 -d > /tmp/common.sh
    echo "${local.worker_b64}" | base64 -d > /tmp/worker.sh
    chmod +x /tmp/common.sh /tmp/worker.sh
    bash /tmp/worker.sh
  USERDATA

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
  }

  tags = merge(local.common_tags, {
    Name = "k8s-worker-01"
    Role = "worker"
  })
}

# ── Worker Node 02 ────────────────────────────────────────────────────────────
resource "aws_instance" "worker_02" {
  ami                         = data.aws_ami.ubuntu_22_04.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = local.subnet_id
  vpc_security_group_ids      = [aws_security_group.k8s_cluster.id]
  associate_public_ip_address = true

  user_data = <<-USERDATA
    #!/bin/bash
    echo "${local.common_b64}" | base64 -d > /tmp/common.sh
    echo "${local.worker_b64}" | base64 -d > /tmp/worker.sh
    chmod +x /tmp/common.sh /tmp/worker.sh
    bash /tmp/worker.sh
  USERDATA

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 20
    delete_on_termination = true
  }

  tags = merge(local.common_tags, {
    Name = "k8s-worker-02"
    Role = "worker"
  })
}
