# CloudVibe Tech — VoteVibe Kubernetes Workshop
## Complete Step-by-Step Guide (AWS EC2 · 1 Master · 2 Workers)

---

# PRE-REQUISITES

## Infrastructure Required

| Node | Role | Instance Type | OS |
|------|------|--------------|-----|
| k8s-master | Control Plane | t3.medium (2 vCPU, 4GB) | Ubuntu 22.04 |
| k8s-worker-01 | Worker Node 1 | t3.medium | Ubuntu 22.04 |
| k8s-worker-02 | Worker Node 2 | t3.medium | Ubuntu 22.04 |

## EC2 Security Group Rules (All 3 Nodes)

| Type | Port Range | Source | Purpose |
|------|-----------|--------|---------|
| SSH | 22 | Your IP | SSH access |
| Custom TCP | 6443 | 0.0.0.0/0 | K8s API Server |
| Custom TCP | 2379-2380 | 10.0.0.0/8 | etcd |
| Custom TCP | 10250-10252 | 10.0.0.0/8 | Kubelet/Controller/Scheduler |
| Custom TCP | 30001-30003 | 0.0.0.0/0 | NodePort Services (VoteVibe) |
| All Traffic | All | Security Group self | Inter-node communication |

---

## Step 0: Kubernetes Cluster Setup (All 3 Nodes)

### 0.1 — Run on ALL 3 nodes (Master + Both Workers)

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Disable swap (Kubernetes requirement)
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Load required kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Set required sysctl parameters
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# Install containerd
sudo apt install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl enable containerd

# Install kubeadm, kubelet, kubectl
sudo apt install -y apt-transport-https ca-certificates curl gpg

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

### 0.2 — Initialize the Master Node (Run ONLY on k8s-master)

```bash
# Initialize the cluster
sudo kubeadm init --pod-network-cidr=10.244.0.0/16

# Set up kubectl for your user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install Flannel CNI (pod networking)
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Verify master node is Ready
kubectl get nodes
# Expected: k8s-master   Ready   control-plane   ...

# Generate the join command (SAVE THIS OUTPUT)
kubeadm token create --print-join-command
```

### 0.3 — Join Worker Nodes (Run on EACH worker)

```bash
# Paste the join command from Step 0.2 (example below — yours will be different)
sudo kubeadm join <MASTER_PRIVATE_IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>
```

### 0.4 — Verify Cluster (Run on Master)

```bash
kubectl get nodes
# Expected output:
# NAME             STATUS   ROLES           AGE   VERSION
# k8s-master       Ready    control-plane   5m    v1.29.x
# k8s-worker-01    Ready    <none>          2m    v1.29.x
# k8s-worker-02    Ready    <none>          2m    v1.29.x

# Label the worker nodes (useful for nodeSelector later)
kubectl label node k8s-worker-01 node-role.kubernetes.io/worker=worker
kubectl label node k8s-worker-02 node-role.kubernetes.io/worker=worker
```

---
---

# DAY 1: THE FOUNDATION & THE FRONTEND

## Goal
Set up the namespace, deploy the Blue Team voting frontend with 2 replicas, and expose it via NodePort. By end of day, visiting `http://<EC2_PUBLIC_IP>:30001` shows the Blue voting page.

---

## Step 1.1 — Transfer YAML Files to Master Node

```bash
# From your local machine, SCP all YAML files to the master node
scp -i your-key.pem 01-namespace.yaml ubuntu@<MASTER_PUBLIC_IP>:~/votevibe/
scp -i your-key.pem 02-blue-configmap.yaml ubuntu@<MASTER_PUBLIC_IP>:~/votevibe/
scp -i your-key.pem 03-blue-deployment.yaml ubuntu@<MASTER_PUBLIC_IP>:~/votevibe/
scp -i your-key.pem 04-blue-service.yaml ubuntu@<MASTER_PUBLIC_IP>:~/votevibe/

# Or transfer all files at once
scp -i your-key.pem *.yaml ubuntu@<MASTER_PUBLIC_IP>:~/votevibe/

# SSH into the master node
ssh -i your-key.pem ubuntu@<MASTER_PUBLIC_IP>
cd ~/votevibe
```

---

## Step 1.2 — Create the Namespace

```bash
# Apply the namespace manifest
kubectl apply -f 01-namespace.yaml

# Verify namespace was created
kubectl get namespaces | grep voting-system

# Inspect the namespace details
kubectl describe namespace voting-system

# Set as default namespace for this session (saves typing -n voting-system)
kubectl config set-context --current --namespace=voting-system
```

**Expected output:**
```
namespace/voting-system created

NAME             STATUS   AGE
voting-system    Active   5s
```

**What just happened:**
- Created an isolated environment called `voting-system`
- All our resources will live inside this namespace
- Labels (`project: votevibe`, `team: cloudvibe-devops`) help identify resources

---

## Step 1.3 — Apply the Blue Team ConfigMap

```bash
# Apply the ConfigMap
kubectl apply -f 02-blue-configmap.yaml

# Verify it exists
kubectl get configmap -n voting-system

# Inspect the data inside it
kubectl describe configmap blue-team-config -n voting-system

# View raw YAML (see all key-value pairs)
kubectl get configmap blue-team-config -n voting-system -o yaml
```

**Expected output:**
```
NAME               DATA   AGE
blue-team-config   9      5s
```

**What just happened:**
- Created a ConfigMap storing non-sensitive configuration
- Keys like `TEAM_NAME`, `BG_HEX`, `ACCENT_HEX` will be injected as env vars into the Blue pods
- ConfigMaps decouple configuration from container images

---

## Step 1.4 — Deploy the Blue Team Application

```bash
# Apply the Deployment
kubectl apply -f 03-blue-deployment.yaml

# Watch pods come up in real time (Ctrl+C to exit)
kubectl get pods -n voting-system -w

# Wait until both replicas are Running
kubectl rollout status deployment/blue-team-deployment -n voting-system
```

**Expected output (after ~45-60 seconds):**
```
NAME                                    READY   STATUS    RESTARTS   AGE
blue-team-deployment-7d8f9b6c4-k9x2p   1/1     Running   0          52s
blue-team-deployment-7d8f9b6c4-m3nq7   1/1     Running   0          52s
```

**What just happened:**
- Kubernetes created 2 pods (replicas) running the Flask voting app
- Each pod pulls `python:3.11-slim`, installs Flask+Gunicorn, and starts the web server
- The RollingUpdate strategy ensures zero-downtime during future updates
- Pod anti-affinity spreads pods across worker nodes for high availability

**If pods are stuck in `ContainerCreating` or `Pending`:**
```bash
kubectl describe pod <POD_NAME> -n voting-system
# Look at the "Events" section at the bottom for error details
```

---

## Step 1.5 — Expose via NodePort Service

```bash
# Apply the Service
kubectl apply -f 04-blue-service.yaml

# Verify service is created
kubectl get service -n voting-system

# Get full service details including endpoints
kubectl describe service blue-team-service -n voting-system

# Confirm endpoints (shows which pod IPs the service routes to)
kubectl get endpoints blue-team-service -n voting-system
```

**Expected output:**
```
NAME                TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
blue-team-service   NodePort   10.96.x.x     <none>        80:30001/TCP   5s
```

---

## Step 1.6 — Verify & Test Everything

### View all resources in namespace
```bash
kubectl get all -n voting-system
```

**Expected output:**
```
NAME                                        READY   STATUS    RESTARTS   AGE
pod/blue-team-deployment-xxx-yyy            1/1     Running   0          2m
pod/blue-team-deployment-xxx-zzz            1/1     Running   0          2m

NAME                        TYPE       CLUSTER-IP    PORT(S)        AGE
service/blue-team-service   NodePort   10.96.x.x     80:30001/TCP   1m

NAME                                   READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/blue-team-deployment   2/2     2            2           2m

NAME                                              DESIRED   CURRENT   READY   AGE
replicaset.apps/blue-team-deployment-xxx          2         2         2       2m
```

### Inspect a specific pod
```bash
# Get pod names
BLUE_POD=$(kubectl get pods -n voting-system -l app=votevibe-blue -o jsonpath='{.items[0].metadata.name}')

# Describe the pod (events, conditions, probes)
kubectl describe pod $BLUE_POD -n voting-system

# View live logs
kubectl logs $BLUE_POD -n voting-system

# Stream logs in real time (Ctrl+C to stop)
kubectl logs $BLUE_POD -n voting-system -f
```

### Exec into a running pod
```bash
kubectl exec -it $BLUE_POD -n voting-system -- /bin/bash

# Inside the pod — test the app locally
curl localhost:5000/healthz
curl -s localhost:5000/ | head -20
exit
```

### Test from the master node
```bash
# Get worker node internal IPs
kubectl get nodes -o wide

# Curl the NodePort directly using a worker node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[1].status.addresses[0].address}')
curl http://$NODE_IP:30001/
curl http://$NODE_IP:30001/healthz
```

### Test from your browser
```
Open: http://<ANY_EC2_PUBLIC_IP>:30001
(Use the public IP of ANY node — master or worker)
```

**Make sure EC2 Security Group allows inbound TCP on port 30001 from your IP.**

### Check which nodes pods are running on
```bash
kubectl get pods -n voting-system -o wide
# The NODE column shows pod distribution across workers
```

---

## Step 1.7 — Debugging Commands (If Something Goes Wrong)

```bash
# Pod stuck in Pending?
kubectl describe pod <POD_NAME> -n voting-system
# Look for "Events" section — usually resource or scheduling issues

# Pod in CrashLoopBackOff?
kubectl logs <POD_NAME> -n voting-system --previous
# Shows logs from the previous crashed container

# Check resource usage (requires metrics-server — installed Day 3)
kubectl top pods -n voting-system
kubectl top nodes

# Check node capacity and allocated resources
kubectl describe node k8s-worker-01 | grep -A 10 "Allocated resources"

# Force delete a stuck pod (use only if necessary)
kubectl delete pod <POD_NAME> -n voting-system --force --grace-period=0
```

---

## Day 1 Checkpoint

At this point you should have:
- [x] `voting-system` namespace created
- [x] `blue-team-config` ConfigMap with team colors/settings
- [x] `blue-team-deployment` with 2 Running pods spread across workers
- [x] `blue-team-service` NodePort exposing port 30001
- [x] Blue voting page visible at `http://<EC2_PUBLIC_IP>:30001`

---
---

# DAY 2: THE CORE LOGIC & CONNECTIVITY

## Goal
Deploy Redis as the backend, deploy the Red Team frontend with Redis integration, and demonstrate Kubernetes service discovery. By end of day, both Red and Blue voting apps are live with Redis storing vote data.

---

## Step 2.1 — Deploy Redis Backend

```bash
# Apply Redis Deployment
kubectl apply -f 05-redis-deployment.yaml

# Apply Redis ClusterIP Service
kubectl apply -f 06-redis-service.yaml

# Watch Redis come up
kubectl rollout status deployment/redis-deployment -n voting-system

# Verify Redis pod is Running
kubectl get pods -n voting-system -l app=redis
```

**Expected output:**
```
NAME                                READY   STATUS    RESTARTS   AGE
redis-deployment-xxx-yyy            1/1     Running   0          30s
```

### Test Redis DNS Resolution (from within the cluster)

```bash
# Run a temporary busybox pod to test DNS
kubectl run dns-test --image=busybox:1.35 --restart=Never -n voting-system \
  --rm -it -- nslookup redis-service.voting-system.svc.cluster.local
```

**Expected output:**
```
Server:    10.96.0.10
Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local
Name:      redis-service.voting-system.svc.cluster.local
Address 1: 10.96.x.x redis-service.voting-system.svc.cluster.local
```

### Test Redis Connectivity

```bash
# Run a temporary Redis container to ping our Redis service
kubectl run redis-test --image=redis:7.2-alpine --restart=Never -n voting-system \
  --rm -it -- redis-cli -h redis-service -p 6379 ping
# Expected: PONG
```

---

## Step 2.2 — Understanding Kubernetes Service DNS

```
Kubernetes DNS pattern:
  <service-name>.<namespace>.svc.cluster.local

So Redis is reachable at:
  redis-service.voting-system.svc.cluster.local:6379

Or (within the same namespace, just):
  redis-service:6379

Service Types:
  ClusterIP    = only internal cluster traffic (Redis uses this)
  NodePort     = external access via node IP + static port (Blue/Red use this)
  LoadBalancer = external via cloud load balancer (AWS ELB, etc.)
```

```bash
# List all services and their types + cluster IPs
kubectl get svc -n voting-system -o wide
```

---

## Step 2.3 — Deploy Red Team ConfigMap

```bash
kubectl apply -f 07-red-configmap.yaml

# Verify
kubectl get configmap -n voting-system
kubectl describe configmap red-team-config -n voting-system
```

**Note:** The Red ConfigMap includes `REDIS_HOST: "redis-service"` and `REDIS_PORT: "6379"` — this is how the Red app knows where to find Redis using Kubernetes DNS.

---

## Step 2.4 — Deploy Red Team Application

```bash
# Apply Red Team Deployment
kubectl apply -f 08-red-deployment.yaml 

# Apply Red Team NodePort Service
kubectl apply -f 09-red-service.yaml

# Monitor rollout
kubectl rollout status deployment/red-team-deployment -n voting-system

# Verify all pods are running
kubectl get pods -n voting-system -o wide
```

**Expected output (all 5 pods running):**
```
NAME                                    READY   STATUS    RESTARTS   AGE   NODE
blue-team-deployment-xxx-aaa            1/1     Running   0          1h    k8s-worker-01
blue-team-deployment-xxx-bbb            1/1     Running   0          1h    k8s-worker-02
red-team-deployment-xxx-ccc             1/1     Running   0          30s   k8s-worker-01
red-team-deployment-xxx-ddd             1/1     Running   0          30s   k8s-worker-02
redis-deployment-xxx-eee                1/1     Running   0          10m   k8s-worker-01
```

---

## Step 2.5 — Labels & Selectors Deep-Dive

```bash
# List pods by team label
kubectl get pods -n voting-system -l team=blue
kubectl get pods -n voting-system -l team=red

# List all frontend pods
kubectl get pods -n voting-system -l tier=frontend

# Multi-label selector (AND logic)
kubectl get pods -n voting-system -l tier=frontend,team=red

# View ALL labels on every pod
kubectl get pods -n voting-system --show-labels

# See which pods each service routes to (via endpoints)
kubectl get endpoints -n voting-system

# Manually check what pods match a service's selector
kubectl get pods -n voting-system -l app=votevibe-red -o wide
kubectl get pods -n voting-system -l app=votevibe-blue -o wide
```

---

## Step 2.6 — Full System Verification

### Overview of all resources
```bash
kubectl get all -n voting-system
```

**Expected output:**
```
NAME                                        READY   STATUS    RESTARTS   AGE
pod/blue-team-deployment-xxx-aaa            1/1     Running   0          1h
pod/blue-team-deployment-xxx-bbb            1/1     Running   0          1h
pod/red-team-deployment-xxx-ccc             1/1     Running   0          5m
pod/red-team-deployment-xxx-ddd             1/1     Running   0          5m
pod/redis-deployment-xxx-eee                1/1     Running   0          15m

NAME                        TYPE        CLUSTER-IP      PORT(S)
service/blue-team-service   NodePort    10.96.x.x       80:30001/TCP
service/red-team-service    NodePort    10.96.x.x       80:30002/TCP
service/redis-service       ClusterIP   10.96.x.x       6379/TCP

NAME                                   READY   UP-TO-DATE   AVAILABLE
deployment.apps/blue-team-deployment   2/2     2            2
deployment.apps/red-team-deployment    2/2     2            2
deployment.apps/redis-deployment       1/1     1            1
```

### Test network connectivity between pods
```bash
# From a Blue pod, can it resolve Redis DNS?
BLUE_POD=$(kubectl get pods -n voting-system -l app=votevibe-blue \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it $BLUE_POD -n voting-system -- \
  python -c "import socket; print(socket.gethostbyname('redis-service'))"
```

### Access both apps from browser
```
Blue Team:  http://<EC2_PUBLIC_IP>:30001
Red Team:   http://<EC2_PUBLIC_IP>:30002
```

### Verify Redis is storing votes
```bash
# Vote a few times on the Red Team page, then check Redis
REDIS_POD=$(kubectl get pods -n voting-system -l app=redis \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it $REDIS_POD -n voting-system -- redis-cli GET red_votes
# Expected: the number of times you voted
```

---

## Step 2.7 — Debugging Network Issues

```bash
# Service endpoints are empty? Selector doesn't match any pods
kubectl describe service red-team-service -n voting-system
# Check "Endpoints:" line — if empty, fix your label selectors

# Pod can't reach redis-service?
kubectl exec -it <POD_NAME> -n voting-system -- \
  sh -c "apt-get update -qq && apt-get install -y -qq netcat-openbsd && nc -zv redis-service 6379"

# Check CoreDNS is running
kubectl get pods -n kube-system | grep coredns
kubectl logs -n kube-system -l k8s-app=kube-dns

# Inspect iptables rules on a worker node (SSH to the node)
ssh -i your-key.pem ubuntu@<WORKER_NODE_IP>
sudo iptables -t nat -L KUBE-SERVICES | grep voting
exit
```

---

## Day 2 Checkpoint

At this point you should have:
- [x] Redis running (1 pod) with ClusterIP service (internal only)
- [x] Red Team deployed (2 pods) with Redis integration
- [x] Red Team accessible at `http://<EC2_PUBLIC_IP>:30002`
- [x] Blue Team still running at `http://<EC2_PUBLIC_IP>:30001`
- [x] Red votes persisting to Redis (survives page refresh)
- [x] Kubernetes DNS resolving `redis-service` from all pods
- [x] Total: 5 pods, 3 services, 2 configmaps

---
---

# DAY 3: PERSISTENCE, CONFIGS & SCALING

## Goal
Add production-grade features: Secrets for Redis auth, PersistentVolumeClaims for data survival across pod restarts, a live Results Dashboard, and Horizontal Pod Autoscaling. By end of day, VoteVibe is fully production-ready.

---

## Step 3.1 — Create the Kubernetes Secret

```bash
# Apply the Secret
kubectl apply -f 10-redis-secret.yaml

# Verify secret exists (values are hidden in describe output)
kubectl get secret redis-secret -n voting-system
kubectl describe secret redis-secret -n voting-system

# Decode a secret value (for verification only — don't do this in production logs)
kubectl get secret redis-secret -n voting-system \
  -o jsonpath='{.data.redis-password}' | base64 -d
echo ""   # Add newline for clean output
# Expected: CloudVibe@Redis2024!
```

**What just happened:**
- Secrets store sensitive data (passwords, tokens, keys) in base64 encoding
- Unlike ConfigMaps, Secrets are not shown in `kubectl describe` output
- In production, use Sealed Secrets, HashiCorp Vault, or AWS Secrets Manager

---

## Step 3.2 — Create Persistent Storage

### Prepare the storage directory on the worker node

```bash
# Find out which worker node Redis will run on
# (We'll pin it to worker-01 via nodeSelector in the deployment)

# SSH to worker-01 and create the directory
ssh -i your-key.pem ubuntu@<WORKER_01_PUBLIC_IP>
sudo mkdir -p /data/redis-votevibe
sudo chmod 777 /data/redis-votevibe
ls -la /data/
exit
```

### Apply PersistentVolume and PersistentVolumeClaim

```bash
# Create the PersistentVolume (cluster-wide resource — no namespace)
kubectl apply -f 11-redis-pv.yaml

# Create the PersistentVolumeClaim (namespaced)
kubectl apply -f 12-redis-pvc.yaml

# Verify PV and PVC are BOUND to each other
kubectl get pv redis-pv
kubectl get pvc redis-pvc -n voting-system
```

**Expected output:**
```
NAME       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   STORAGECLASS
redis-pv   2Gi        RWO            Retain           Bound    manual

NAME        STATUS   VOLUME     CAPACITY   ACCESS MODES   STORAGECLASS
redis-pvc   Bound    redis-pv   2Gi        RWO            manual
```

**PVC Status meanings:**
- `Pending` = No matching PV found (check storageClassName and capacity)
- `Bound` = Successfully matched and attached
- `Lost` = PV was deleted while PVC still existed

```bash
# Get detailed info about the PVC binding
kubectl describe pvc redis-pvc -n voting-system
```

---

## Step 3.3 — Upgrade Redis to Use Persistent Storage + Secret

**IMPORTANT:** Before upgrading, update `13-redis-deployment-v2.yaml` with your actual worker node name:

```bash
# Get your worker node names
kubectl get nodes
# Replace "k8s-worker-01" in 13-redis-deployment-v2.yaml with your actual node name
```

Edit the `nodeSelector` section in `13-redis-deployment-v2.yaml`:
```yaml
      nodeSelector:
        kubernetes.io/hostname: <YOUR_ACTUAL_WORKER_01_HOSTNAME>
```

Then apply:

```bash
# Apply the updated Redis deployment (rolling update)
kubectl apply -f 13-redis-deployment-v2.yaml

# Watch the rolling update happen
kubectl rollout status deployment/redis-deployment -n voting-system

# Verify the new pod is running
kubectl get pods -n voting-system -l app=redis

# Verify the PVC is mounted inside the pod
REDIS_POD=$(kubectl get pods -n voting-system -l app=redis \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it $REDIS_POD -n voting-system -- df -h /data
kubectl exec -it $REDIS_POD -n voting-system -- ls -la /data
```

### Test Persistence (Critical Verification)

```bash
# Step 1: Write a test value to Redis
kubectl exec -it $REDIS_POD -n voting-system -- \
  redis-cli -a 'CloudVibe@Redis2024!' SET test_key "persistence_works"
# Expected: OK

# Step 2: Delete the Redis pod (Deployment will recreate it automatically)
kubectl delete pod $REDIS_POD -n voting-system

# Step 3: Wait for the new pod to be ready
kubectl get pods -n voting-system -l app=redis -w
# Wait until STATUS shows Running and READY shows 1/1, then Ctrl+C

# Step 4: Verify data survived the pod restart
NEW_REDIS_POD=$(kubectl get pods -n voting-system -l app=redis \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it $NEW_REDIS_POD -n voting-system -- \
  redis-cli -a 'CloudVibe@Redis2024!' GET test_key
# Expected: "persistence_works"
```

If you see `"persistence_works"` — data survived the pod deletion and recreation.

---

## Step 3.4 — Also Update Blue Team for Redis (Optional but Recommended)

The Blue Team from Day 1 stores votes only in memory. To have Blue votes appear on the scoreboard too, redeploy the Blue app with Redis support. The updated `02-blue-configmap.yaml` and `03-blue-deployment.yaml` (which you already have with Redis integration) should be re-applied:

```bash
# Re-apply the updated Blue ConfigMap (now includes REDIS_HOST, REDIS_PORT, VOTE_KEY)
kubectl apply -f 02-blue-configmap.yaml

# Re-apply the updated Blue Deployment (now has Redis client code)
kubectl apply -f 03-blue-deployment.yaml

# Watch the rolling update
kubectl rollout status deployment/blue-team-deployment -n voting-system
```

---

## Step 3.5 — Deploy the Results Dashboard

```bash
# Apply Results ConfigMap
kubectl apply -f 14-results-configmap.yaml

# Apply Results Deployment
kubectl apply -f 15-results-deployment.yaml

# Apply Results NodePort Service
kubectl apply -f 16-results-service.yaml

# Wait for rollout
kubectl rollout status deployment/results-deployment -n voting-system

# Verify
kubectl get pods -n voting-system -l app=results-dashboard
kubectl get service results-service -n voting-system
```

### Test the Scoreboard

```
Open: http://<EC2_PUBLIC_IP>:30003
```

You should see:
- A dark-themed scoreboard with Blue and Red team cards
- Vote counts pulled from Redis
- Progress bars showing percentage split
- "LEADING" badge on the team with more votes
- Auto-refreshes every 3 seconds

---

## Step 3.6 — Install Metrics Server & HPAs

### Install Metrics Server

```bash
# Install metrics-server (required for HPA to read CPU/memory metrics)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch for self-signed certs (needed on kubeadm clusters)
kubectl patch deployment metrics-server -n kube-system \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# Wait for metrics-server to be ready
kubectl rollout status deployment/metrics-server -n kube-system

# Verify metrics are flowing (wait 60-90 seconds after install)
kubectl top nodes
kubectl top pods -n voting-system
```

**Expected output (after ~90 seconds):**
```
NAME             CPU(cores)   MEMORY(bytes)
k8s-master       150m         1200Mi
k8s-worker-01    80m          800Mi
k8s-worker-02    75m          750Mi
```

### Apply HPAs

```bash
# Apply HPA for Blue Team
kubectl apply -f 17-hpa-blue.yaml

# Apply HPA for Red Team
kubectl apply -f 18-hpa-red.yaml

# View HPA status
kubectl get hpa -n voting-system

# Detailed view
kubectl describe hpa blue-team-hpa -n voting-system
kubectl describe hpa red-team-hpa -n voting-system
```

**Expected output:**
```
NAME            REFERENCE                       TARGETS         MINPODS   MAXPODS   REPLICAS
blue-team-hpa   Deployment/blue-team-deployment  5%/60%          2         8         2
red-team-hpa    Deployment/red-team-deployment   4%/60%          2         8         2
```

---

## Step 3.7 — Manual Scaling Exercise

```bash
# Scale Blue Team to 4 replicas manually
kubectl scale deployment/blue-team-deployment --replicas=4 -n voting-system

# Watch pods scale up and distribute across nodes
kubectl get pods -n voting-system -l app=votevibe-blue -o wide -w

# Verify 4 pods running
kubectl get deployment blue-team-deployment -n voting-system

# Scale back down to 2
kubectl scale deployment/blue-team-deployment --replicas=2 -n voting-system

# Watch pods terminate gracefully
kubectl get pods -n voting-system -l app=votevibe-blue -w
```

---

## Step 3.8 — Simulate Load for HPA (Optional)

Open two terminal windows (both SSH'd to the master node):

**Terminal 1 — Generate Load:**
```bash
# Run a load generator pod
kubectl run load-gen --image=busybox:1.35 --restart=Never -n voting-system \
  --rm -it -- sh -c "while true; do wget -q -O- http://blue-team-service/vote; done"
```

**Terminal 2 — Watch HPA React:**
```bash
# Watch HPA in real time
watch kubectl get hpa -n voting-system

# Also watch pod count increase
watch kubectl get pods -n voting-system -l app=votevibe-blue
```

After CPU exceeds 60%, HPA will scale up (adding up to 2 pods per 30s).
Press `Ctrl+C` in Terminal 1 to stop load. HPA will scale down after 2 minutes.

---

## Step 3.9 — Rolling Update & Rollback Exercise

```bash
# Simulate a version update by changing an env var (triggers rolling update)
kubectl set env deployment/blue-team-deployment \
  TEAM_NAME="Blue Team v2.0" \
  -n voting-system

# Watch rolling update (zero downtime — old pods stay until new ones are ready)
kubectl rollout status deployment/blue-team-deployment -n voting-system

# Verify — visit http://<EC2_IP>:30001 — should now show "Blue Team v2.0"

# View rollout history
kubectl rollout history deployment/blue-team-deployment -n voting-system

# Rollback to previous version
kubectl rollout undo deployment/blue-team-deployment -n voting-system

# Verify — should now show "Blue Team" again
kubectl rollout status deployment/blue-team-deployment -n voting-system

# Rollback to a specific revision
kubectl rollout history deployment/blue-team-deployment -n voting-system
# Pick a revision number from the output
kubectl rollout undo deployment/blue-team-deployment --to-revision=1 -n voting-system
```

---

## Step 3.10 — Final Full System Health Check

```bash
echo "========================================"
echo "  VOTEVIBE COMPLETE SYSTEM STATUS CHECK"
echo "========================================"

echo ""
echo "=== NAMESPACE ==="
kubectl get namespace voting-system

echo ""
echo "=== ALL RESOURCES ==="
kubectl get all -n voting-system

echo ""
echo "=== PERSISTENT VOLUMES ==="
kubectl get pv,pvc -n voting-system

echo ""
echo "=== CONFIGMAPS ==="
kubectl get configmaps -n voting-system

echo ""
echo "=== SECRETS ==="
kubectl get secrets -n voting-system

echo ""
echo "=== HPA STATUS ==="
kubectl get hpa -n voting-system

echo ""
echo "=== RESOURCE USAGE ==="
kubectl top pods -n voting-system

echo ""
echo "=== NODE DISTRIBUTION ==="
kubectl get pods -n voting-system -o wide

echo ""
echo "=== ENDPOINTS ==="
kubectl get endpoints -n voting-system

echo ""
echo "========================================"
echo "  ACCESS URLS"
echo "========================================"
echo "  Blue Team:   http://<EC2_PUBLIC_IP>:30001"
echo "  Red Team:    http://<EC2_PUBLIC_IP>:30002"
echo "  Scoreboard:  http://<EC2_PUBLIC_IP>:30003"
echo "========================================"
```

---

## Day 3 Checkpoint

At this point you should have:
- [x] `redis-secret` with base64-encoded Redis password
- [x] PV + PVC bound (2Gi) — Redis data survives pod restarts
- [x] Redis v2 deployment using PVC + Secret authentication
- [x] Results Dashboard live at `http://<EC2_IP>:30003`
- [x] HPAs for both teams (2-8 replicas, 60% CPU target)
- [x] Metrics-server installed and reporting CPU/memory
- [x] Rolling update and rollback demonstrated
- [x] Total: 6 pods, 4 services, 3 configmaps, 1 secret, 1 PV, 1 PVC, 2 HPAs

---
---

# CLEANUP (End of Workshop)

```bash
# Delete all resources in the namespace
kubectl delete all --all -n voting-system

# Delete ConfigMaps and Secrets
kubectl delete configmaps --all -n voting-system
kubectl delete secrets --all -n voting-system

# Delete HPAs
kubectl delete hpa --all -n voting-system

# Delete PVC
kubectl delete pvc --all -n voting-system

# Delete PV (cluster-scoped, not in namespace)
kubectl delete pv redis-pv

# Delete the entire namespace (removes EVERYTHING inside it)
kubectl delete namespace voting-system

# Verify cleanup
kubectl get all -n voting-system
# Expected: "No resources found in voting-system namespace."

# Clean up storage on worker node
ssh -i your-key.pem ubuntu@<WORKER_01_PUBLIC_IP>
sudo rm -rf /data/redis-votevibe
exit
```

---

# ARCHITECTURE SUMMARY

```
Internet
    │
    ▼
EC2 Public IP (any node)
    │
    ├── :30001 ──▶ NodePort Service (blue-team-service)
    │                    │
    │              ┌─────┴──────┐
    │              │            │
    │         Pod (Blue)   Pod (Blue)
    │         Worker-01    Worker-02
    │
    ├── :30002 ──▶ NodePort Service (red-team-service)
    │                    │
    │              ┌─────┴──────┐
    │              │            │
    │          Pod (Red)    Pod (Red)
    │          Worker-01    Worker-02
    │
    └── :30003 ──▶ NodePort Service (results-service)
                        │
                   Pod (Results)
                        │
                        ▼
              ClusterIP (redis-service) :6379
                        │
                   Pod (Redis)
                        │
                   PVC (2Gi)
                        │
                   PV (hostPath)
                        │
              /data/redis-votevibe
              (Worker Node 01 disk)
```

---

# K8s CONCEPTS COVERED

| Concept | K8s Object | Day | File |
|---------|-----------|-----|------|
| Resource isolation | Namespace | 1 | 01-namespace.yaml |
| Non-sensitive config | ConfigMap | 1 | 02-blue-configmap.yaml |
| Running workloads | Deployment | 1 | 03-blue-deployment.yaml |
| Expose externally | NodePort Service | 1 | 04-blue-service.yaml |
| Backend workload | Deployment | 2 | 05-redis-deployment.yaml |
| Internal communication | ClusterIP Service | 2 | 06-redis-service.yaml |
| DNS-based discovery | Service DNS | 2 | 07-red-configmap.yaml |
| Label routing | Selectors | 2 | 08-red-deployment.yaml |
| Health checking | Liveness/Readiness Probes | 2 | 08-red-deployment.yaml |
| Sensitive config | Secret | 3 | 10-redis-secret.yaml |
| Persistent storage | PV + PVC | 3 | 11/12-redis-pv/pvc.yaml |
| Zero-downtime updates | Rolling update | 3 | 13-redis-deployment-v2.yaml |
| Auto-scaling | HorizontalPodAutoscaler | 3 | 17/18-hpa-blue/red.yaml |
| Rollback | `kubectl rollout undo` | 3 | (command) |

---

# QUICK KUBECTL CHEATSHEET

| Command | Purpose |
|---------|---------|
| `kubectl apply -f <file>` | Create/update resources from YAML |
| `kubectl get all -n voting-system` | List all resources in namespace |
| `kubectl get pods -o wide` | Show pods with node placement |
| `kubectl describe pod <name>` | Detailed pod info + events |
| `kubectl logs <pod> -f` | Stream logs |
| `kubectl logs <pod> --previous` | Logs from crashed container |
| `kubectl exec -it <pod> -- bash` | Shell into pod |
| `kubectl rollout status deploy/<name>` | Watch rolling update |
| `kubectl rollout undo deploy/<name>` | Rollback deployment |
| `kubectl rollout history deploy/<name>` | View update history |
| `kubectl scale deploy/<name> --replicas=N` | Manual scale |
| `kubectl get hpa` | View autoscaler status |
| `kubectl top pods` | Resource usage (needs metrics-server) |
| `kubectl get endpoints` | See which pods services route to |
| `kubectl delete ns voting-system` | Delete everything |
