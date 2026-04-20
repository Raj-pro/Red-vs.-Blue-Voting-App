#!/bin/bash
# ============================================================
# VoteVibe Workshop — Master Node Bootstrap
# Runs ONLY on k8s-master
# Matches Workshop Guide Steps 0.2 + storage prep
# ============================================================
set -euo pipefail
exec > /var/log/k8s-master-setup.log 2>&1

echo "[master] Starting master node init — $(date)"

# ── 1. Run common prerequisites first ────────────────────────
# /tmp/common.sh is placed there by the user_data bootstrap
bash /tmp/common.sh

# ── 2. Initialise the cluster ────────────────────────────────
kubeadm init --pod-network-cidr=10.244.0.0/16

# ── 3. Set up kubectl for the ubuntu user ────────────────────
USER_HOME="/home/ubuntu"
mkdir -p "$USER_HOME/.kube"
cp /etc/kubernetes/admin.conf "$USER_HOME/.kube/config"
chown ubuntu:ubuntu "$USER_HOME/.kube/config"

# Also make available for root (useful during debug)
mkdir -p /root/.kube
cp /etc/kubernetes/admin.conf /root/.kube/config

# ── 4. Install Flannel CNI ───────────────────────────────────
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# ── 5. Wait for master to be Ready ───────────────────────────
echo "[master] Waiting for master node to become Ready..."
for i in $(seq 1 30); do
  STATUS=$(kubectl get node --no-headers 2>/dev/null | awk '{print $2}' | head -1)
  if [ "$STATUS" = "Ready" ]; then
    echo "[master] Master node is Ready"
    break
  fi
  echo "[master] Attempt $i/30 — status: $STATUS, retrying in 10s..."
  sleep 10
done

# ── 6. Generate worker join command ──────────────────────────
JOIN_CMD=$(kubeadm token create --print-join-command)
echo "[master] Join command: $JOIN_CMD"

# Store in a file so the Terraform output can read it (for reference)
echo "$JOIN_CMD" > /home/ubuntu/join-command.txt
chown ubuntu:ubuntu /home/ubuntu/join-command.txt
chmod 600 /home/ubuntu/join-command.txt

# ── 7. Label helper (run after workers join) ─────────────────
cat <<'SCRIPT' > /home/ubuntu/label-workers.sh
#!/bin/bash
# Run this AFTER both workers have joined
kubectl label node k8s-worker-01 node-role.kubernetes.io/worker=worker --overwrite
kubectl label node k8s-worker-02 node-role.kubernetes.io/worker=worker --overwrite
kubectl get nodes
SCRIPT
chmod +x /home/ubuntu/label-workers.sh
chown ubuntu:ubuntu /home/ubuntu/label-workers.sh

# ── 8. Create votevibe working directory ─────────────────────
mkdir -p /home/ubuntu/votevibe
chown ubuntu:ubuntu /home/ubuntu/votevibe

echo "[master] Master setup complete — $(date)"
echo "[master] Join command saved to /home/ubuntu/join-command.txt"
echo "[master] Run 'cat ~/join-command.txt' to get the worker join command"
