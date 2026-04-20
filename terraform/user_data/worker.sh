#!/bin/bash
# ============================================================
# VoteVibe Workshop — Worker Node Bootstrap
# Runs on k8s-worker-01 and k8s-worker-02
# Matches Workshop Guide Step 0.1
# NOTE: You still need to run the kubeadm join command manually
#       (copy it from /home/ubuntu/join-command.txt on the master)
# ============================================================
set -euo pipefail
exec > /var/log/k8s-worker-setup.log 2>&1

echo "[worker] Starting worker node prerequisite setup — $(date)"

# Run common prerequisites
bash /tmp/common.sh

# Create the Redis data directory (for PV hostPath — only needed on worker-01)
mkdir -p /data/redis-votevibe
chmod 777 /data/redis-votevibe

echo "[worker] Worker prerequisites complete — $(date)"
echo "[worker] Next step: SSH to master, get join command from ~/join-command.txt"
echo "[worker] Then run the join command on this worker as root."
