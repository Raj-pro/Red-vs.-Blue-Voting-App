#!/bin/bash
# ============================================================
# VoteVibe Workshop — Common K8s Prerequisites
# Runs on ALL nodes (master + workers)
# Matches Workshop Guide Step 0.1
# ============================================================
set -euo pipefail
exec > /var/log/k8s-common-setup.log 2>&1

echo "[common] Starting K8s prerequisite setup — $(date)"

# ── 1. System update ─────────────────────────────────────────
apt-get update -y
apt-get upgrade -y

# ── 2. Disable swap ──────────────────────────────────────────
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# ── 3. Kernel modules ────────────────────────────────────────
cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# ── 4. sysctl params ─────────────────────────────────────────
cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# ── 5. containerd ────────────────────────────────────────────
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

# ── 6. kubeadm / kubelet / kubectl ───────────────────────────
apt-get install -y apt-transport-https ca-certificates curl gpg

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' \
  > /etc/apt/sources.list.d/kubernetes.list

apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

echo "[common] Prerequisites installed successfully — $(date)"
