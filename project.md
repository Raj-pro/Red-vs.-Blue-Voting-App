# ☁️ CloudVibe Tech — Kubernetes Workshop
## "Red vs. Blue Voting App" | 3-Day Hands-On Training
### Infrastructure: AWS EC2 · 1 Master · 2 Worker Nodes · Provisioned via Terraform

---

# Infrastructure — Terraform

The cluster infrastructure is fully automated with Terraform (see [terraform/](terraform/)).
Running `terraform apply` provisions:

| Resource | Details |
|---|---|
| VPC | `10.50.0.0/16` with public subnet, IGW, route table |
| EC2 × 3 | `t3.medium` Ubuntu 22.04 — `k8s-master`, `k8s-worker-01`, `k8s-worker-02` |
| Security Group | SSH (your IP), K8s API :6443, etcd :2379-2380, kubelet :10250-10252, NodePorts :30001-30003, all inter-node |
| Bootstrap | `common.sh` runs on all nodes; `master.sh` runs kubeadm init + Flannel CNI |

## Quick Start

```bash
# 1. Configure credentials
export AWS_PROFILE=raj          # or whichever profile has valid credentials

# 2. Fill in your values
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit: key_name, your_ip (curl -s checkip.amazonaws.com && echo "/32")

# 3. Provision
terraform init
terraform plan
terraform apply

# 4. Wait ~5 min for bootstrap, then get the worker join command
terraform output get_join_command   # shows ssh + cat command
# SSH to each worker and run:  sudo kubeadm join <output>

# 5. Transfer YAML manifests to master and follow the workshop days
terraform output scp_yaml_command
```

## Terraform File Map

```
terraform/
├── main.tf               # Provider, Ubuntu 22.04 AMI, VPC + subnet + IGW + route table
├── variables.tf          # region, key_name, your_ip, instance_type, vpc_id, subnet_id
├── security_group.tf     # All 6 inbound rules + all-outbound
├── ec2.tf                # 3 aws_instance resources + base64-encoded user_data
├── outputs.tf            # Public IPs, SSH commands, app URLs, join command helper
├── terraform.tfvars.example
└── user_data/
    ├── common.sh         # Step 0.1 — kubeadm/kubelet/kubectl prereqs (all nodes)
    ├── master.sh         # Step 0.2 — kubeadm init, Flannel, saves join command
    └── worker.sh         # Step 0.1 + creates /data/redis-votevibe for PV (Day 3)
```

## Useful Commands

```bash
# Check bootstrap progress on any node
ssh -i <key>.pem ubuntu@$(terraform output -raw master_public_ip) \
  "tail -f /var/log/k8s-master-setup.log"

# Destroy everything when done
terraform destroy
```

---

# 🎬 PHASE 1: The Office Scenario

## The Meeting That Started It All

It's 9:47 AM on a Tuesday. You've just poured your second cup of coffee when your Slack pings.

> **Sarah Chen** [Engineering Manager] 9:47 AM
> *Hey, got 10 minutes? My office. Not urgent, just exciting. 🚀*

You walk in to find Sarah standing at her whiteboard, marker in hand, already mid-thought.

---

**Sarah:** "Okay, so — you know how leadership has been pushing for us to modernize our internal tooling stack? Well, I just got sign-off on something fun. We're building an internal polling app. Nothing crazy — Red Team vs. Blue Team, let the company vote on stuff. Pizza vs. Tacos for the Friday lunch. Coffee vs. Tea. Classic stuff."

She turns to face you.

**Sarah:** "But here's the catch — and this is the *good* part — they want it containerized, orchestrated, and running on Kubernetes. Full production-grade. Namespaces, Deployments, Services, ConfigMaps, Secrets, persistent storage — the whole nine yards. This is going to be our internal showcase for the DevOps roadmap."

She tosses you a sticky note with three words on it: **Red. Blue. Kubernetes.**

**Sarah:** "You've got three days. I'll check in every morning. Don't make me regret this."

She grins and points you toward the door.

**You:** "Three days. Got it. How many replicas are we talking?"

**Sarah:** "Start with two. We'll scale when we inevitably go viral internally. Now go."

---

**Your Mission:**
Build and deploy `VoteVibe` — a Red vs. Blue themed voting application on Kubernetes that demonstrates every major K8s component, running on an EC2-backed cluster.

---

---

# 📅 DAY 1: The Foundation & The Frontend

## 🎯 The Goal

Today we lay the groundwork for the entire system. We'll set up our custom namespace, understand the Kubernetes object model, and deploy the **Blue Team** voting frontend as a live, accessible application. By end of day, you'll have a blue-themed web page reachable via your EC2 public IP.

**Components Built Today:**
- `voting-system` Namespace
- Blue Team Deployment (Python/Flask app)
- NodePort Service (external access)
- Basic Pod inspection & debugging

---

## 👩‍💼 Manager's Check-in

> *"Good morning! Quick question — if I open a browser right now and go to our EC2 IP, will I see something blue? No? Then get back to work. I believe in you. ☕"*
> — **Sarah, 9:02 AM**

---

## 📦 Step 1: Build the Blue Voting App Container

We'll use a Flask app baked into a custom Docker image. Since we're in a training environment, we'll use an inline `ConfigMap` to inject the HTML, avoiding a private registry. The app will be served via `gunicorn` using the `python:3.11-slim` base image from DockerHub.

### `blue-app.py` — The Flask Application

```python
# blue-app.py
import os
from flask import Flask, render_template_string, request, redirect, url_for

app = Flask(__name__)

TEAM_COLOR = os.environ.get("TEAM_COLOR", "blue")
TEAM_NAME  = os.environ.get("TEAM_NAME",  "Blue Team")
BG_COLOR   = os.environ.get("BG_HEX",     "#1a237e")
ACCENT     = os.environ.get("ACCENT_HEX", "#42a5f5")

TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VoteVibe — {{ team_name }}</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            background: {{ bg_color }};
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            color: white;
        }
        .card {
            background: rgba(255,255,255,0.08);
            border: 2px solid {{ accent }};
            border-radius: 24px;
            padding: 60px 80px;
            text-align: center;
            backdrop-filter: blur(10px);
            box-shadow: 0 20px 60px rgba(0,0,0,0.4);
        }
        h1 { font-size: 3.5rem; font-weight: 800; margin-bottom: 8px; }
        .tagline { font-size: 1.2rem; opacity: 0.7; margin-bottom: 40px; }
        .vote-count {
            font-size: 5rem;
            font-weight: 900;
            color: {{ accent }};
            margin: 20px 0;
        }
        .vote-btn {
            background: {{ accent }};
            color: #000;
            border: none;
            padding: 18px 60px;
            font-size: 1.4rem;
            font-weight: 700;
            border-radius: 50px;
            cursor: pointer;
            transition: transform 0.2s, box-shadow 0.2s;
            text-transform: uppercase;
            letter-spacing: 2px;
        }
        .vote-btn:hover {
            transform: scale(1.05);
            box-shadow: 0 8px 25px rgba(0,0,0,0.3);
        }
        .footer {
            margin-top: 30px;
            font-size: 0.85rem;
            opacity: 0.5;
        }
        .pod-info {
            margin-top: 20px;
            background: rgba(0,0,0,0.2);
            border-radius: 8px;
            padding: 10px 20px;
            font-size: 0.8rem;
            font-family: monospace;
            opacity: 0.6;
        }
    </style>
</head>
<body>
    <div class="card">
        <h1>🔵 {{ team_name }}</h1>
        <p class="tagline">CloudVibe Internal Voting System</p>
        <div class="vote-count">{{ vote_count }}</div>
        <p style="margin-bottom: 20px; opacity: 0.7;">votes cast</p>
        <form method="POST" action="/vote">
            <button class="vote-btn" type="submit">Cast Your Vote</button>
        </form>
        <div class="pod-info">
            Pod: {{ pod_name }} | Namespace: {{ namespace }}
        </div>
        <p class="footer">VoteVibe v1.0 · CloudVibe Tech Internal Tools</p>
    </div>
</body>
</html>
"""

votes = 0

@app.route("/")
def index():
    return render_template_string(
        TEMPLATE,
        team_name=TEAM_NAME,
        bg_color=BG_COLOR,
        accent=ACCENT,
        vote_count=votes,
        pod_name=os.environ.get("HOSTNAME", "unknown"),
        namespace=os.environ.get("POD_NAMESPACE", "unknown")
    )

@app.route("/vote", methods=["POST"])
def vote():
    global votes
    votes += 1
    return redirect(url_for("index"))

@app.route("/healthz")
def health():
    return {"status": "ok", "team": TEAM_NAME}, 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
```

### `Dockerfile` — For Reference (Pre-built image used in workshop)

```dockerfile
FROM python:3.11-slim
WORKDIR /app
RUN pip install flask gunicorn --no-cache-dir
COPY blue-app.py .
EXPOSE 5000
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "blue-app:app"]
```

> **Workshop Note:** For this training, we use the pre-built public image `cloudvibe/votevibe:blue-v1` to avoid needing a private registry. In production, you'd push to ECR or Docker Hub.

---

## 📋 YAML Manifests — Day 1

### `01-namespace.yaml` — The Foundation

```yaml
# 01-namespace.yaml
# Purpose: Isolate all VoteVibe resources in their own namespace
apiVersion: v1
kind: Namespace
metadata:
  name: voting-system
  labels:
    project: votevibe
    team: cloudvibe-devops
    environment: workshop
  annotations:
    description: "CloudVibe VoteVibe polling application namespace"
    owner: "platform-team@cloudvibe.io"
```

### `02-blue-configmap.yaml` — App Configuration

```yaml
# 02-blue-configmap.yaml
# Purpose: Store non-sensitive Blue Team configuration
apiVersion: v1
kind: ConfigMap
metadata:
  name: blue-team-config
  namespace: voting-system
  labels:
    app: votevibe-blue
    team: blue
data:
  # Team identity
  TEAM_COLOR: "blue"
  TEAM_NAME:  "Blue Team"
  # Visual theme
  BG_HEX:     "#1a237e"
  ACCENT_HEX: "#42a5f5"
  # App settings
  APP_PORT:   "5000"
  LOG_LEVEL:  "INFO"
```

### `03-blue-deployment.yaml` — The Workload

```yaml
# 03-blue-deployment.yaml
# Purpose: Deploy the Blue Team voting frontend with 2 replicas
apiVersion: apps/v1
kind: Deployment
metadata:
  name: blue-team-deployment
  namespace: voting-system
  labels:
    app: votevibe-blue
    tier: frontend
    team: blue
    version: "1.0"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: votevibe-blue
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0          # Zero-downtime deployments
  template:
    metadata:
      labels:
        app: votevibe-blue
        tier: frontend
        team: blue
    spec:
      containers:
        - name: votevibe-blue
          image: python:3.11-slim
          imagePullPolicy: IfNotPresent
          command: ["/bin/sh", "-c"]
          args:
            - |
              pip install flask gunicorn --quiet &&
              cat > /app.py << 'PYEOF'
              import os
              from flask import Flask, render_template_string, request, redirect, url_for
              app = Flask(__name__)
              TEAM_NAME  = os.environ.get("TEAM_NAME",  "Blue Team")
              BG_COLOR   = os.environ.get("BG_HEX",     "#1a237e")
              ACCENT     = os.environ.get("ACCENT_HEX", "#42a5f5")
              TEMPLATE = """<!DOCTYPE html><html><head><title>VoteVibe</title>
              <style>*{margin:0;padding:0;box-sizing:border-box}
              body{background:{{ bg }};font-family:sans-serif;min-height:100vh;
              display:flex;align-items:center;justify-content:center;color:white}
              .card{background:rgba(255,255,255,.1);border:2px solid {{ ac }};
              border-radius:24px;padding:60px 80px;text-align:center}
              h1{font-size:3rem;font-weight:800}
              .cnt{font-size:5rem;font-weight:900;color:{{ ac }};margin:20px 0}
              .btn{background:{{ ac }};color:#000;border:none;padding:16px 50px;
              font-size:1.3rem;font-weight:700;border-radius:50px;cursor:pointer}
              .info{margin-top:20px;font-size:.75rem;opacity:.5;font-family:monospace}
              </style></head><body><div class="card">
              <h1>🔵 {{ nm }}</h1><p style="opacity:.6;margin:8px 0 30px">CloudVibe Internal Voting</p>
              <div class="cnt">{{ vc }}</div><p style="opacity:.6;margin-bottom:20px">votes</p>
              <form method="POST" action="/vote">
              <button class="btn" type="submit">CAST VOTE</button></form>
              <div class="info">Pod: {{ pn }} | NS: {{ ns }}</div>
              </div></body></html>"""
              votes = 0
              @app.route("/")
              def index():
                  global votes
                  return render_template_string(TEMPLATE,nm=TEAM_NAME,bg=BG_COLOR,
                      ac=ACCENT,vc=votes,pn=os.environ.get("HOSTNAME","?"),
                      ns=os.environ.get("POD_NAMESPACE","?"))
              @app.route("/vote",methods=["POST"])
              def vote():
                  global votes; votes += 1
                  return redirect("/")
              @app.route("/healthz")
              def health(): return {"status":"ok"},200
              if __name__=="__main__": app.run(host="0.0.0.0",port=5000)
              PYEOF
              gunicorn --bind 0.0.0.0:5000 --workers 2 app:app
          ports:
            - containerPort: 5000
              name: http
              protocol: TCP
          # Inject ConfigMap values as environment variables
          envFrom:
            - configMapRef:
                name: blue-team-config
          # Inject additional runtime env vars
          env:
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
          # Resource limits — always set these in production
          resources:
            requests:
              memory: "128Mi"
              cpu: "100m"
            limits:
              memory: "256Mi"
              cpu: "300m"
          # Liveness probe — K8s restarts pod if this fails
          livenessProbe:
            httpGet:
              path: /healthz
              port: 5000
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 3
          # Readiness probe — pod only gets traffic when this passes
          readinessProbe:
            httpGet:
              path: /healthz
              port: 5000
            initialDelaySeconds: 15
            periodSeconds: 5
      # Spread pods across worker nodes for high availability
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    - key: app
                      operator: In
                      values:
                        - votevibe-blue
                topologyKey: kubernetes.io/hostname
```

### `04-blue-service.yaml` — External Access

```yaml
# 04-blue-service.yaml
# Purpose: Expose the Blue Team app via NodePort (EC2 public IP accessible)
apiVersion: v1
kind: Service
metadata:
  name: blue-team-service
  namespace: voting-system
  labels:
    app: votevibe-blue
    tier: frontend
  annotations:
    description: "NodePort service for Blue Team voting UI"
spec:
  type: NodePort
  selector:
    app: votevibe-blue          # Must match Deployment pod labels
  ports:
    - name: http
      protocol: TCP
      port: 80                  # Service port (internal cluster)
      targetPort: 5000          # Container port
      nodePort: 30001           # EC2 external port (range: 30000-32767)
  sessionAffinity: ClientIP     # Sticky sessions — same client hits same pod
```

---

## 🖥️ Step-by-Step kubectl Commands — Day 1

### Phase 1A: Create the Namespace

```bash
# Apply the namespace manifest
kubectl apply -f 01-namespace.yaml

# Verify namespace was created
kubectl get namespaces | grep voting-system

# Inspect the namespace details
kubectl describe namespace voting-system

# Set as default namespace for this session (optional but convenient)
kubectl config set-context --current --namespace=voting-system
```

**Expected output:**
```
namespace/voting-system created
NAME             STATUS   AGE
voting-system    Active   5s
```

### Phase 1B: Apply ConfigMap

```bash
# Apply the ConfigMap
kubectl apply -f 02-blue-configmap.yaml

# Verify it exists
kubectl get configmap -n voting-system

# Inspect the data inside it
kubectl describe configmap blue-team-config -n voting-system

# View raw YAML
kubectl get configmap blue-team-config -n voting-system -o yaml
```

### Phase 1C: Deploy the Blue App

```bash
# Apply the Deployment
kubectl apply -f 03-blue-deployment.yaml

# Watch pods come up in real time
kubectl get pods -n voting-system -w

# Wait until both replicas are Running
kubectl rollout status deployment/blue-team-deployment -n voting-system
```

**Expected output (after ~45 seconds):**
```
NAME                                    READY   STATUS    RESTARTS   AGE
blue-team-deployment-7d8f9b6c4-k9x2p   1/1     Running   0          52s
blue-team-deployment-7d8f9b6c4-m3nq7   1/1     Running   0          52s
```

### Phase 1D: Expose via NodePort

```bash
# Apply the Service
kubectl apply -f 04-blue-service.yaml

# Verify service is created
kubectl get service -n voting-system

# Get full service details including endpoints
kubectl describe service blue-team-service -n voting-system

# Confirm endpoints (shows which pods the service routes to)
kubectl get endpoints blue-team-service -n voting-system
```

### Phase 1E: Verify & Debug

```bash
# ---- VIEW ALL RESOURCES IN NAMESPACE ----
kubectl get all -n voting-system

# ---- INSPECT A SPECIFIC POD ----
# Get pod names first
BLUE_POD=$(kubectl get pods -n voting-system -l app=votevibe-blue -o jsonpath='{.items[0].metadata.name}')

# Describe the pod (events, conditions, probes)
kubectl describe pod $BLUE_POD -n voting-system

# View live logs
kubectl logs $BLUE_POD -n voting-system

# Stream logs in real time
kubectl logs $BLUE_POD -n voting-system -f

# ---- EXEC INTO A RUNNING POD ----
kubectl exec -it $BLUE_POD -n voting-system -- /bin/bash

# Inside the pod — test the app locally
curl localhost:5000/healthz
curl -s localhost:5000/ | head -20
exit

# ---- TEST FROM MASTER NODE ----
# Get a worker node internal IP
kubectl get nodes -o wide

# Curl the NodePort directly
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[1].status.addresses[0].address}')
curl http://$NODE_IP:30001/

# ---- ACCESS FROM BROWSER ----
# Open: http://<YOUR_EC2_PUBLIC_IP>:30001
# (Ensure EC2 Security Group allows TCP inbound on port 30001)
```

### EC2 Security Group Note

```bash
# Add this inbound rule to your EC2 Security Group:
# Type: Custom TCP
# Port range: 30001
# Source: 0.0.0.0/0 (or your IP for security)

# Verify the port is listening on the node
ssh ec2-user@<WORKER_NODE_IP> "ss -tlnp | grep 30001"
```

### 🐛 Common Debugging Commands

```bash
# Pod stuck in Pending?
kubectl describe pod <POD_NAME> -n voting-system
# Look for "Events" section — usually resource or scheduling issues

# Pod in CrashLoopBackOff?
kubectl logs <POD_NAME> -n voting-system --previous

# Check resource usage
kubectl top pods -n voting-system
kubectl top nodes

# Check node capacity
kubectl describe node <NODE_NAME> | grep -A 10 "Allocated resources"

# Force delete a stuck pod
kubectl delete pod <POD_NAME> -n voting-system --force --grace-period=0
```

---

## 📣 The 5-Minute Standup — Day 1

> *Read this aloud to your team at end of day:*

```
✅ Day 1 Standup — VoteVibe Blue Frontend

• Created the 'voting-system' namespace with proper labels and annotations
  to isolate all project resources from other cluster workloads.

• Deployed the Blue Team Flask voting application using a Deployment
  with 2 replicas for high availability.

• Configured the app via a ConfigMap (blue-team-config) injecting team
  color, name, and hex values as environment variables — no hardcoding.

• Exposed the Blue frontend via a NodePort Service on port 30001,
  making it accessible via the EC2 public IP from any browser.

• Validated liveness and readiness probes are functioning, confirmed
  pod anti-affinity is spreading replicas across both worker nodes.

• Verified end-to-end: http://<EC2_IP>:30001 shows the Blue voting UI.

Blockers: None.
Tomorrow: Red Team deployment, ClusterIP for internal comms, Services deep-dive.
```

---
---

# 📅 DAY 2: The Core Logic & Connectivity

## 🎯 The Goal

With our foundation solid, today we deploy the **Red Team** frontend and introduce the Kubernetes networking model. We'll cover ClusterIP (internal) vs. NodePort (external) Services, and wire up a Redis backend for vote counting. By end of day, both Red and Blue voting apps are live and independently accessible, with Redis storing vote data internally.

**Components Built Today:**
- Red Team Deployment (mirroring Blue, different theme)
- Redis Deployment + ClusterIP Service
- Red Team NodePort Service
- Service-to-Service communication (how apps talk internally)
- Labels & Selectors deep-dive

---

## 👩‍💼 Manager's Check-in

> *"Okay I can see the blue page. Love it. But right now it's just one team — that's not a competition, that's just sadness. Where's Red? Also, are votes actually being saved anywhere or is this all smoke and mirrors? I need answers. Red. Redis. Real persistence. Let's go. 🔴"*
> — **Sarah, 9:15 AM**

---

## 📋 YAML Manifests — Day 2

### `05-redis-deployment.yaml` — The Backend

```yaml
# 05-redis-deployment.yaml
# Purpose: Deploy Redis as the vote storage backend
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-deployment
  namespace: voting-system
  labels:
    app: redis
    tier: backend
    component: cache
spec:
  replicas: 1                   # Redis is stateful — single instance for now
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
        tier: backend
    spec:
      containers:
        - name: redis
          image: redis:7.2-alpine
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 6379
              name: redis
          command: ["redis-server"]
          args:
            - "--requirepass"
            - "$(REDIS_PASSWORD)"             # Injected from Secret (Day 3)
            - "--appendonly"
            - "yes"
            - "--save"
            - "60 1"
          env:
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: redis-secret           # Created in Day 3
                  key: redis-password
                  optional: true              # Won't crash if secret missing yet
          resources:
            requests:
              memory: "64Mi"
              cpu: "50m"
            limits:
              memory: "128Mi"
              cpu: "200m"
          livenessProbe:
            exec:
              command: ["redis-cli", "ping"]
            initialDelaySeconds: 15
            periodSeconds: 10
          readinessProbe:
            exec:
              command: ["redis-cli", "ping"]
            initialDelaySeconds: 5
            periodSeconds: 5
          volumeMounts:
            - name: redis-data
              mountPath: /data               # Redis persistence path
      volumes:
        - name: redis-data
          emptyDir: {}                       # Temporary — replaced with PVC on Day 3
```

### `06-redis-service.yaml` — Internal Service (ClusterIP)

```yaml
# 06-redis-service.yaml
# Purpose: ClusterIP service — Redis only accessible INSIDE the cluster
# This is the DEFAULT service type in Kubernetes
apiVersion: v1
kind: Service
metadata:
  name: redis-service
  namespace: voting-system
  labels:
    app: redis
    tier: backend
  annotations:
    description: "Internal ClusterIP — Redis not exposed externally by design"
spec:
  type: ClusterIP              # Default — no external access, only in-cluster DNS
  selector:
    app: redis
  ports:
    - name: redis
      protocol: TCP
      port: 6379               # Service port
      targetPort: 6379         # Container port
```

### `07-red-configmap.yaml` — Red Team Config

```yaml
# 07-red-configmap.yaml
# Purpose: Mirror of blue-team-config but for Red Team
apiVersion: v1
kind: ConfigMap
metadata:
  name: red-team-config
  namespace: voting-system
  labels:
    app: votevibe-red
    team: red
data:
  TEAM_COLOR:   "red"
  TEAM_NAME:    "Red Team"
  BG_HEX:       "#7f0000"
  ACCENT_HEX:   "#ef5350"
  APP_PORT:     "5000"
  LOG_LEVEL:    "INFO"
  REDIS_HOST:   "redis-service"      # Kubernetes DNS name of Redis ClusterIP service
  REDIS_PORT:   "6379"
  VOTE_KEY:     "red_votes"
```

### `08-red-deployment.yaml` — Red Team Frontend

```yaml
# 08-red-deployment.yaml
# Purpose: Deploy the Red Team voting frontend with Redis integration
apiVersion: apps/v1
kind: Deployment
metadata:
  name: red-team-deployment
  namespace: voting-system
  labels:
    app: votevibe-red
    tier: frontend
    team: red
    version: "1.0"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: votevibe-red
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: votevibe-red
        tier: frontend
        team: red
    spec:
      containers:
        - name: votevibe-red
          image: python:3.11-slim
          imagePullPolicy: IfNotPresent
          command: ["/bin/sh", "-c"]
          args:
            - |
              pip install flask gunicorn redis --quiet &&
              cat > /app.py << 'PYEOF'
              import os
              import redis as redislib
              from flask import Flask, render_template_string, redirect

              app = Flask(__name__)

              TEAM_NAME  = os.environ.get("TEAM_NAME",  "Red Team")
              BG_COLOR   = os.environ.get("BG_HEX",     "#7f0000")
              ACCENT     = os.environ.get("ACCENT_HEX", "#ef5350")
              REDIS_HOST = os.environ.get("REDIS_HOST", "redis-service")
              REDIS_PORT = int(os.environ.get("REDIS_PORT", "6379"))
              REDIS_PASS = os.environ.get("REDIS_PASSWORD", None)
              VOTE_KEY   = os.environ.get("VOTE_KEY", "red_votes")

              # Connect to Redis (graceful degradation if unavailable)
              try:
                  r = redislib.Redis(host=REDIS_HOST, port=REDIS_PORT,
                                     password=REDIS_PASS, decode_responses=True,
                                     socket_connect_timeout=3)
                  r.ping()
                  REDIS_OK = True
              except Exception as e:
                  print(f"Redis connection failed: {e}")
                  r = None
                  REDIS_OK = False

              TEMPLATE = """
              <!DOCTYPE html><html><head><title>VoteVibe - {{ nm }}</title>
              <style>
              *{margin:0;padding:0;box-sizing:border-box}
              body{background:{{ bg }};font-family:sans-serif;min-height:100vh;
                   display:flex;align-items:center;justify-content:center;color:white}
              .card{background:rgba(255,255,255,.1);border:2px solid {{ ac }};
                    border-radius:24px;padding:60px 80px;text-align:center}
              h1{font-size:3rem;font-weight:800}
              .cnt{font-size:5rem;font-weight:900;color:{{ ac }};margin:20px 0}
              .btn{background:{{ ac }};color:#fff;border:none;padding:16px 50px;
                   font-size:1.3rem;font-weight:700;border-radius:50px;cursor:pointer}
              .status{font-size:.75rem;margin-top:16px;padding:8px 16px;
                      border-radius:8px;display:inline-block;
                      background: {{ "rgba(0,200,0,.2)" if redis_ok else "rgba(200,0,0,.2)" }}}
              .info{margin-top:16px;font-size:.75rem;opacity:.5;font-family:monospace}
              </style></head>
              <body><div class="card">
              <h1>🔴 {{ nm }}</h1>
              <p style="opacity:.6;margin:8px 0 30px">CloudVibe Internal Voting</p>
              <div class="cnt">{{ vc }}</div>
              <p style="opacity:.6;margin-bottom:20px">votes</p>
              <form method="POST" action="/vote">
              <button class="btn" type="submit">CAST VOTE</button></form>
              <div class="status">
                Redis: {{ "✅ Connected" if redis_ok else "❌ Disconnected (in-memory)" }}
              </div>
              <div class="info">Pod: {{ pn }} | NS: {{ ns }}</div>
              </div></body></html>
              """

              @app.route("/")
              def index():
                  vc = 0
                  if REDIS_OK and r:
                      try:
                          vc = int(r.get(VOTE_KEY) or 0)
                      except:
                          pass
                  return render_template_string(TEMPLATE, nm=TEAM_NAME, bg=BG_COLOR,
                      ac=ACCENT, vc=vc, redis_ok=REDIS_OK,
                      pn=os.environ.get("HOSTNAME","?"),
                      ns=os.environ.get("POD_NAMESPACE","?"))

              @app.route("/vote", methods=["POST"])
              def vote():
                  if REDIS_OK and r:
                      try:
                          r.incr(VOTE_KEY)
                      except:
                          pass
                  return redirect("/")

              @app.route("/healthz")
              def health():
                  return {"status": "ok", "redis": REDIS_OK}, 200

              if __name__ == "__main__":
                  app.run(host="0.0.0.0", port=5000)
              PYEOF
              gunicorn --bind 0.0.0.0:5000 --workers 2 app:app
          ports:
            - containerPort: 5000
              name: http
          envFrom:
            - configMapRef:
                name: red-team-config
          env:
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: redis-secret
                  key: redis-password
                  optional: true
          resources:
            requests:
              memory: "128Mi"
              cpu: "100m"
            limits:
              memory: "256Mi"
              cpu: "300m"
          livenessProbe:
            httpGet:
              path: /healthz
              port: 5000
            initialDelaySeconds: 45
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /healthz
              port: 5000
            initialDelaySeconds: 20
            periodSeconds: 5
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchExpressions:
                    - key: app
                      operator: In
                      values: [votevibe-red]
                topologyKey: kubernetes.io/hostname
```

### `09-red-service.yaml` — Red Team NodePort

```yaml
# 09-red-service.yaml
# Purpose: Expose Red Team UI externally via NodePort
apiVersion: v1
kind: Service
metadata:
  name: red-team-service
  namespace: voting-system
  labels:
    app: votevibe-red
    tier: frontend
spec:
  type: NodePort
  selector:
    app: votevibe-red
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 5000
      nodePort: 30002            # Different port from Blue (30001)
  sessionAffinity: ClientIP
```

---

## 🖥️ Step-by-Step kubectl Commands — Day 2

### Phase 2A: Deploy Redis Backend

```bash
# Deploy Redis
kubectl apply -f 05-redis-deployment.yaml
kubectl apply -f 06-redis-service.yaml

# Watch Redis come up
kubectl rollout status deployment/redis-deployment -n voting-system

# Verify Redis service DNS resolution (from within cluster)
kubectl run dns-test --image=busybox:1.35 --restart=Never -n voting-system \
  --rm -it -- nslookup redis-service.voting-system.svc.cluster.local

# Test Redis connectivity from inside cluster
kubectl run redis-test --image=redis:7.2-alpine --restart=Never -n voting-system \
  --rm -it -- redis-cli -h redis-service -p 6379 ping
```

### Phase 2B: Understanding Service DNS

```bash
# Kubernetes DNS pattern:
# <service-name>.<namespace>.svc.cluster.local
# So Redis is reachable at:
#   redis-service.voting-system.svc.cluster.local:6379
# OR (within same namespace) just:
#   redis-service:6379

# List all services and their cluster IPs
kubectl get svc -n voting-system -o wide

# Explain the difference:
# ClusterIP  = only internal cluster traffic
# NodePort   = external via node IP + static port
# LoadBalancer = external via cloud LB (AWS ELB, etc.)
```

### Phase 2C: Deploy Red Team

```bash
# Apply Red Team manifests
kubectl apply -f 07-red-configmap.yaml
kubectl apply -f 08-red-deployment.yaml
kubectl apply -f 09-red-service.yaml

# Monitor rollout
kubectl rollout status deployment/red-team-deployment -n voting-system

# Verify all pods are running
kubectl get pods -n voting-system -o wide

# Check which nodes pods landed on (verify anti-affinity)
kubectl get pods -n voting-system -l tier=frontend -o wide
```

### Phase 2D: Labels & Selectors Deep-Dive

```bash
# List resources by label
kubectl get pods -n voting-system -l team=blue
kubectl get pods -n voting-system -l team=red
kubectl get pods -n voting-system -l tier=frontend

# Multi-label selector
kubectl get pods -n voting-system -l tier=frontend,team=red

# View all labels on pods
kubectl get pods -n voting-system --show-labels

# Verify service selector is matching correct pods
kubectl get endpoints -n voting-system

# Manually check what pods a service would route to
kubectl get pods -n voting-system -l app=votevibe-red -o wide
```

### Phase 2E: Full System Verification

```bash
# ---- OVERVIEW ----
kubectl get all -n voting-system

# Expected output:
# NAME                                       READY   STATUS
# pod/blue-team-deployment-xxx-xxx           1/1     Running
# pod/blue-team-deployment-xxx-yyy           1/1     Running
# pod/red-team-deployment-xxx-aaa            1/1     Running
# pod/red-team-deployment-xxx-bbb            1/1     Running
# pod/redis-deployment-xxx-zzz              1/1     Running
#
# NAME                    TYPE        CLUSTER-IP      PORT(S)
# service/blue-team-service  NodePort  10.96.x.x   80:30001/TCP
# service/red-team-service   NodePort  10.96.x.x   80:30002/TCP
# service/redis-service      ClusterIP 10.96.x.x   6379/TCP

# ---- NETWORK CONNECTIVITY TEST ----
# From a Blue pod, can it reach Redis?
BLUE_POD=$(kubectl get pods -n voting-system -l app=votevibe-blue \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it $BLUE_POD -n voting-system -- \
  python -c "import socket; print(socket.gethostbyname('redis-service'))"

# ---- ACCESS BOTH APPS ----
# Blue Team:  http://<EC2_PUBLIC_IP>:30001
# Red Team:   http://<EC2_PUBLIC_IP>:30002

# ---- REDIS VOTE CHECK ----
REDIS_POD=$(kubectl get pods -n voting-system -l app=redis \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it $REDIS_POD -n voting-system -- \
  redis-cli GET red_votes
```

### 🐛 Debugging Network Issues

```bash
# Service not routing correctly?
kubectl describe service red-team-service -n voting-system
# Check "Endpoints:" — if empty, selector doesn't match any pods

# Pod can't reach redis-service?
kubectl exec -it <POD> -n voting-system -- nc -zv redis-service 6379

# Check cluster DNS is working
kubectl get pods -n kube-system | grep coredns
kubectl logs -n kube-system -l k8s-app=kube-dns

# Inspect iptables rules on a node (SSH to node)
sudo iptables -t nat -L KUBE-SERVICES | grep voting
```

---

## 📣 The 5-Minute Standup — Day 2

> *Read this aloud to your team at end of day:*

```
✅ Day 2 Standup — Core Logic & Connectivity

• Deployed Redis 7.2 as our vote storage backend using a single-replica
  Deployment with a ClusterIP Service — intentionally not exposed externally.

• Deployed the Red Team Flask frontend with Redis integration, matching
  Blue Team architecture with independent ConfigMap for theming.

• Demonstrated Kubernetes service discovery via DNS:
  'redis-service.voting-system.svc.cluster.local' resolves automatically
  to the Redis ClusterIP — no hardcoded IPs anywhere.

• Both voting UIs are live and accessible:
  Blue → http://<EC2_IP>:30001 | Red → http://<EC2_IP>:30002

• Red Team votes are persisting to Redis and surviving pod restarts
  (within the session — PVC persistence coming tomorrow).

• Labels and selectors deep-dive complete — team understands how
  Services use selectors to route traffic to the correct pod subset.

Blockers: Redis auth not yet fully wired (Secret coming Day 3).
Tomorrow: ConfigMaps advanced, Secrets, PersistentVolumeClaims, HPA scaling.
```

---
---

# 📅 DAY 3: Persistence, Configs & Scaling

## 🎯 The Goal

The final day brings production-grade features: **Secrets** for sensitive data, **PersistentVolumeClaims** to survive pod restarts, an advanced **ConfigMap** for the results dashboard, and **Horizontal Pod Autoscaling** to handle vote surges. We'll also tie everything together with a live scoreboard. By end of day, VoteVibe is fully production-ready.

**Components Built Today:**
- Kubernetes Secret (Redis password)
- PersistentVolume + PersistentVolumeClaim (Redis data)
- Results Dashboard Deployment
- Replica scaling (manual + HPA)
- Full system review & cleanup commands

---

## 👩‍💼 Manager's Check-in

> *"I went home last night and voted Red seventeen times. Then I cleared my browser and voted Blue twelve times. This morning, all those votes are gone. FIX. THAT. Also — I showed this to the CEO and she said 'what happens if everyone votes at once?' So... yeah, we need scaling. Today. No pressure. 😅"*
> — **Sarah, 8:58 AM**

---

## 📋 YAML Manifests — Day 3

### `10-redis-secret.yaml` — The Secret

```yaml
# 10-redis-secret.yaml
# Purpose: Store Redis password as a Kubernetes Secret
# IMPORTANT: In production, use Sealed Secrets, Vault, or AWS Secrets Manager
# The values below are base64 encoded (NOT encrypted — just encoded)
#
# To encode: echo -n "yourpassword" | base64
# To decode: echo "eW91cnBhc3N3b3Jk" | base64 -d
apiVersion: v1
kind: Secret
metadata:
  name: redis-secret
  namespace: voting-system
  labels:
    app: redis
    security: credentials
  annotations:
    description: "Redis authentication credentials — rotate every 90 days"
type: Opaque
data:
  # "CloudVibe@Redis2024!" base64 encoded
  redis-password: Q2xvdWRWaWJlQFJlZGlzMjAyNCE=
  # "voting-system-redis" base64 encoded
  redis-username: dm90aW5nLXN5c3RlbS1yZWRpcw==
```

### `11-redis-pv.yaml` — PersistentVolume (Storage Class)

```yaml
# 11-redis-pv.yaml
# Purpose: Define physical storage on the cluster node
# For EC2/KDM: Using hostPath (node-local storage)
# In production: Use AWS EBS CSI driver with StorageClass
apiVersion: v1
kind: PersistentVolume
metadata:
  name: redis-pv
  labels:
    type: local
    app: redis
    purpose: vote-storage
spec:
  storageClassName: manual
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteOnce          # Single node read-write
  persistentVolumeReclaimPolicy: Retain   # Don't delete data when PVC released
  hostPath:
    path: "/data/redis-votevibe"          # Directory on the worker node
    type: DirectoryOrCreate
```

### `12-redis-pvc.yaml` — PersistentVolumeClaim

```yaml
# 12-redis-pvc.yaml
# Purpose: Claim storage for Redis — binds to the PV above
# Think of it as: PV = the actual disk, PVC = the reservation ticket
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: redis-pvc
  namespace: voting-system
  labels:
    app: redis
spec:
  storageClassName: manual
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi              # Must be <= PV capacity
```

### `13-redis-deployment-v2.yaml` — Redis with Persistent Storage

```yaml
# 13-redis-deployment-v2.yaml
# Purpose: Update Redis to use PVC instead of emptyDir
# This replaces the Day 2 redis-deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-deployment
  namespace: voting-system
  labels:
    app: redis
    tier: backend
    version: "2.0"
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
        tier: backend
    spec:
      containers:
        - name: redis
          image: redis:7.2-alpine
          imagePullPolicy: IfNotPresent
          ports:
            - containerPort: 6379
          command: ["redis-server"]
          args:
            - "--requirepass"
            - "$(REDIS_PASSWORD)"
            - "--appendonly"
            - "yes"
            - "--save"
            - "30 1"                     # Save every 30s if at least 1 change
            - "--dir"
            - "/data"
          env:
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: redis-secret
                  key: redis-password
          resources:
            requests:
              memory: "64Mi"
              cpu: "50m"
            limits:
              memory: "128Mi"
              cpu: "200m"
          livenessProbe:
            exec:
              command:
                - redis-cli
                - -a
                - $(REDIS_PASSWORD)
                - ping
            initialDelaySeconds: 15
            periodSeconds: 10
          volumeMounts:
            - name: redis-persistent-storage
              mountPath: /data               # Redis writes here — NOW PERSISTENT
      volumes:
        - name: redis-persistent-storage
          persistentVolumeClaim:
            claimName: redis-pvc            # Bind to our PVC
      # Pin Redis to a specific node (since hostPath PV is node-local)
      nodeSelector:
        kubernetes.io/hostname: k8s-worker-01   # Adjust to your actual worker node name
```

### `14-results-configmap.yaml` — Results Dashboard Config

```yaml
# 14-results-configmap.yaml
# Purpose: Config for the scoreboard/results dashboard app
apiVersion: v1
kind: ConfigMap
metadata:
  name: results-config
  namespace: voting-system
  labels:
    app: results-dashboard
data:
  APP_TITLE:    "VoteVibe Live Results"
  BLUE_VOTE_KEY: "blue_votes"
  RED_VOTE_KEY:  "red_votes"
  REDIS_HOST:    "redis-service"
  REDIS_PORT:    "6379"
  REFRESH_RATE:  "3"             # Auto-refresh every 3 seconds
  # Inline HTML template — stored in ConfigMap for easy modification
  DASHBOARD_TITLE: "🏆 CloudVibe VoteVibe — Live Scoreboard"
```

### `15-results-deployment.yaml` — Live Scoreboard

```yaml
# 15-results-deployment.yaml
# Purpose: A live scoreboard showing Red vs. Blue vote counts
apiVersion: apps/v1
kind: Deployment
metadata:
  name: results-deployment
  namespace: voting-system
  labels:
    app: results-dashboard
    tier: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: results-dashboard
  template:
    metadata:
      labels:
        app: results-dashboard
        tier: frontend
    spec:
      containers:
        - name: results
          image: python:3.11-slim
          command: ["/bin/sh", "-c"]
          args:
            - |
              pip install flask redis --quiet &&
              cat > /results.py << 'PYEOF'
              import os, time
              from flask import Flask, render_template_string
              import redis as redislib

              app = Flask(__name__)
              REDIS_HOST = os.environ.get("REDIS_HOST", "redis-service")
              REDIS_PORT = int(os.environ.get("REDIS_PORT", 6379))
              REDIS_PASS = os.environ.get("REDIS_PASSWORD", None)
              BLUE_KEY   = os.environ.get("BLUE_VOTE_KEY", "blue_votes")
              RED_KEY    = os.environ.get("RED_VOTE_KEY", "red_votes")
              REFRESH    = os.environ.get("REFRESH_RATE", "3")

              try:
                  r = redislib.Redis(host=REDIS_HOST, port=REDIS_PORT,
                                     password=REDIS_PASS, decode_responses=True,
                                     socket_connect_timeout=3)
                  r.ping(); REDIS_OK = True
              except:
                  r = None; REDIS_OK = False

              TEMPLATE = """
              <!DOCTYPE html><html><head>
              <meta charset="UTF-8">
              <meta http-equiv="refresh" content="{{ refresh }}">
              <title>VoteVibe Results</title>
              <style>
              *{margin:0;padding:0;box-sizing:border-box}
              body{background:#111;font-family:sans-serif;color:white;min-height:100vh;
                   display:flex;flex-direction:column;align-items:center;justify-content:center;
                   padding:40px 20px}
              h1{font-size:2.5rem;font-weight:900;text-align:center;margin-bottom:8px;
                 background:linear-gradient(90deg,#42a5f5,#ef5350);
                 -webkit-background-clip:text;-webkit-text-fill-color:transparent}
              .subtitle{opacity:.5;margin-bottom:50px;text-align:center}
              .scoreboard{display:flex;gap:30px;width:100%;max-width:800px}
              .team{flex:1;border-radius:20px;padding:40px;text-align:center;
                    position:relative;overflow:hidden}
              .blue-card{background:linear-gradient(135deg,#1a237e,#1565c0);
                         border:2px solid #42a5f5}
              .red-card{background:linear-gradient(135deg,#7f0000,#b71c1c);
                        border:2px solid #ef5350}
              .team-icon{font-size:3rem;margin-bottom:10px}
              .team-name{font-size:1.4rem;font-weight:700;margin-bottom:20px}
              .vote-count{font-size:5rem;font-weight:900;line-height:1}
              .vote-label{opacity:.6;margin-top:8px;font-size:.9rem}
              .bar-container{width:100%;background:rgba(0,0,0,.3);border-radius:8px;
                             height:12px;margin-top:20px;overflow:hidden}
              .bar-blue{background:#42a5f5;height:100%;border-radius:8px;
                        transition:width .5s ease}
              .bar-red{background:#ef5350;height:100%;border-radius:8px;
                       transition:width .5s ease}
              .winner-badge{background:gold;color:#000;padding:4px 16px;
                            border-radius:20px;font-weight:700;font-size:.85rem;
                            margin-top:12px;display:inline-block}
              .footer{margin-top:40px;opacity:.4;font-size:.8rem;text-align:center}
              .total{margin-bottom:30px;font-size:1.1rem;opacity:.6}
              </style></head><body>
              <h1>🏆 VoteVibe Live Results</h1>
              <p class="subtitle">CloudVibe Tech Internal Polling System</p>
              <p class="total">Total Votes Cast: <strong>{{ total }}</strong></p>
              <div class="scoreboard">
                <div class="team blue-card">
                  <div class="team-icon">🔵</div>
                  <div class="team-name">Blue Team</div>
                  <div class="vote-count">{{ blue }}</div>
                  <div class="vote-label">votes</div>
                  <div class="bar-container">
                    <div class="bar-blue" style="width:{{ blue_pct }}%"></div>
                  </div>
                  <div>{{ "%.1f"|format(blue_pct) }}%</div>
                  {% if blue > red %}<div class="winner-badge">👑 LEADING</div>{% endif %}
                </div>
                <div class="team red-card">
                  <div class="team-icon">🔴</div>
                  <div class="team-name">Red Team</div>
                  <div class="vote-count">{{ red }}</div>
                  <div class="vote-label">votes</div>
                  <div class="bar-container">
                    <div class="bar-red" style="width:{{ red_pct }}%"></div>
                  </div>
                  <div>{{ "%.1f"|format(red_pct) }}%</div>
                  {% if red > blue %}<div class="winner-badge">👑 LEADING</div>{% endif %}
                </div>
              </div>
              <div class="footer">
                Auto-refreshes every {{ refresh }}s |
                Redis: {{ "✅ Connected" if redis_ok else "❌ Down" }} |
                Pod: {{ pod }}
              </div>
              </body></html>
              """

              @app.route("/")
              def index():
                  blue = red = 0
                  if REDIS_OK and r:
                      try:
                          blue = int(r.get(BLUE_KEY) or 0)
                          red  = int(r.get(RED_KEY) or 0)
                      except: pass
                  total = blue + red
                  blue_pct = (blue/total*100) if total > 0 else 50
                  red_pct  = (red/total*100)  if total > 0 else 50
                  return render_template_string(TEMPLATE,
                      blue=blue, red=red, total=total,
                      blue_pct=blue_pct, red_pct=red_pct,
                      redis_ok=REDIS_OK, refresh=REFRESH,
                      pod=os.environ.get("HOSTNAME","?"))

              @app.route("/healthz")
              def health(): return {"status":"ok"},200

              if __name__ == "__main__":
                  app.run(host="0.0.0.0", port=5000)
              PYEOF
              python /results.py
          ports:
            - containerPort: 5000
          envFrom:
            - configMapRef:
                name: results-config
          env:
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: redis-secret
                  key: redis-password
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
          resources:
            requests:
              memory: "64Mi"
              cpu: "50m"
            limits:
              memory: "128Mi"
              cpu: "200m"
          livenessProbe:
            httpGet:
              path: /healthz
              port: 5000
            initialDelaySeconds: 30
            periodSeconds: 10
```

### `16-results-service.yaml` — Scoreboard Service

```yaml
# 16-results-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: results-service
  namespace: voting-system
  labels:
    app: results-dashboard
spec:
  type: NodePort
  selector:
    app: results-dashboard
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 5000
      nodePort: 30003            # Third external port for the scoreboard
```

### `17-hpa-blue.yaml` — Horizontal Pod Autoscaler

```yaml
# 17-hpa-blue.yaml
# Purpose: Auto-scale Blue Team pods based on CPU usage
# Requires: metrics-server installed on cluster
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: blue-team-hpa
  namespace: voting-system
  labels:
    app: votevibe-blue
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: blue-team-deployment
  minReplicas: 2               # Never go below 2 (HA requirement)
  maxReplicas: 8               # Max 8 pods under heavy load
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60    # Scale up if avg CPU > 60%
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 70    # Scale up if avg memory > 70%
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 30    # Wait 30s before scaling up again
      policies:
        - type: Pods
          value: 2
          periodSeconds: 30             # Add max 2 pods per 30s
    scaleDown:
      stabilizationWindowSeconds: 120   # Wait 2min before scaling down
      policies:
        - type: Pods
          value: 1
          periodSeconds: 60             # Remove max 1 pod per 60s
```

### `18-hpa-red.yaml` — HPA for Red Team

```yaml
# 18-hpa-red.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: red-team-hpa
  namespace: voting-system
  labels:
    app: votevibe-red
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: red-team-deployment
  minReplicas: 2
  maxReplicas: 8
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60
  behavior:
    scaleUp:
      stabilizationWindowSeconds: 30
      policies:
        - type: Pods
          value: 2
          periodSeconds: 30
    scaleDown:
      stabilizationWindowSeconds: 120
      policies:
        - type: Pods
          value: 1
          periodSeconds: 60
```

---

## 🖥️ Step-by-Step kubectl Commands — Day 3

### Phase 3A: Secrets & Storage

```bash
# ---- CREATE THE SECRET ----
kubectl apply -f 10-redis-secret.yaml

# Verify secret exists (values are hidden)
kubectl get secret redis-secret -n voting-system
kubectl describe secret redis-secret -n voting-system

# Decode a secret value (for verification only)
kubectl get secret redis-secret -n voting-system \
  -o jsonpath='{.data.redis-password}' | base64 -d
echo ""   # Add newline

# ---- CREATE PERSISTENT VOLUME & CLAIM ----
# First, create the directory on the worker node
# SSH to your worker node:
ssh ec2-user@<WORKER_NODE_IP>
sudo mkdir -p /data/redis-votevibe
sudo chmod 777 /data/redis-votevibe
exit

# Apply PV and PVC
kubectl apply -f 11-redis-pv.yaml
kubectl apply -f 12-redis-pvc.yaml

# Verify PV and PVC are bound to each other
kubectl get pv redis-pv
kubectl get pvc redis-pvc -n voting-system

# PVC STATUS MEANINGS:
# Pending  = No matching PV found
# Bound    = Successfully matched and attached  ✅
# Lost     = PV was deleted while PVC existed

kubectl describe pvc redis-pvc -n voting-system
```

### Phase 3B: Upgrade Redis to Persistent Storage

```bash
# Update Redis deployment to use PVC (rolling update)
kubectl apply -f 13-redis-deployment-v2.yaml

# Watch the rolling update
kubectl rollout status deployment/redis-deployment -n voting-system

# Verify the PVC is mounted
REDIS_POD=$(kubectl get pods -n voting-system -l app=redis \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it $REDIS_POD -n voting-system -- df -h /data
kubectl exec -it $REDIS_POD -n voting-system -- ls -la /data

# Test persistence — set a value, delete pod, verify it survives
kubectl exec -it $REDIS_POD -n voting-system -- \
  redis-cli -a 'CloudVibe@Redis2024!' SET test_key "persistence_works"

# Delete the Redis pod (Deployment will recreate it)
kubectl delete pod $REDIS_POD -n voting-system

# Wait for new pod
kubectl get pods -n voting-system -l app=redis -w

# Verify data survived the pod restart
NEW_REDIS_POD=$(kubectl get pods -n voting-system -l app=redis \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -it $NEW_REDIS_POD -n voting-system -- \
  redis-cli -a 'CloudVibe@Redis2024!' GET test_key
# Expected: "persistence_works" 🎉
```

### Phase 3C: Deploy Results Dashboard

```bash
# Apply results manifests
kubectl apply -f 14-results-configmap.yaml
kubectl apply -f 15-results-deployment.yaml
kubectl apply -f 16-results-service.yaml

# Wait for rollout
kubectl rollout status deployment/results-deployment -n voting-system

# Verify
kubectl get all -n voting-system
```

### Phase 3D: Metrics Server & HPA

```bash
# Install metrics-server (if not already installed on your KDM cluster)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch metrics-server for EC2 (needed for self-signed certs)
kubectl patch deployment metrics-server -n kube-system \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# Wait for metrics-server to be ready
kubectl rollout status deployment/metrics-server -n kube-system

# Verify metrics are flowing (takes 60-90 seconds)
kubectl top nodes
kubectl top pods -n voting-system

# Apply HPAs
kubectl apply -f 17-hpa-blue.yaml
kubectl apply -f 18-hpa-red.yaml

# View HPA status
kubectl get hpa -n voting-system
kubectl describe hpa blue-team-hpa -n voting-system
```

### Phase 3E: Manual Scaling Exercise

```bash
# ---- MANUAL SCALE ----
# Scale Blue Team to 4 replicas manually
kubectl scale deployment/blue-team-deployment --replicas=4 -n voting-system

# Watch pods scale up across nodes
kubectl get pods -n voting-system -l app=votevibe-blue -o wide -w

# Scale back down to 2
kubectl scale deployment/blue-team-deployment --replicas=2 -n voting-system

# ---- SIMULATE LOAD FOR HPA ----
# Run a load test from within the cluster
kubectl run load-gen --image=busybox:1.35 --restart=Never -n voting-system \
  --rm -it -- sh -c "while true; do wget -q -O- http://blue-team-service/vote; done"

# In another terminal — watch HPA react
watch kubectl get hpa -n voting-system
watch kubectl get pods -n voting-system

# Stop the load test (Ctrl+C) and watch scale-down (2 min stabilization window)
```

### Phase 3F: Rolling Update Exercise

```bash
# Simulate a version update
# Update an environment variable (triggers rolling update)
kubectl set env deployment/blue-team-deployment \
  TEAM_NAME="Blue Team v2.0" \
  -n voting-system

# Watch rolling update (zero downtime)
kubectl rollout status deployment/blue-team-deployment -n voting-system

# View rollout history
kubectl rollout history deployment/blue-team-deployment -n voting-system

# Rollback if something goes wrong
kubectl rollout undo deployment/blue-team-deployment -n voting-system

# Rollback to a specific revision
kubectl rollout undo deployment/blue-team-deployment \
  --to-revision=1 -n voting-system
```

### Phase 3G: Full System Health Check

```bash
# ============================================================
# COMPLETE VOTEVIBE SYSTEM STATUS CHECK
# ============================================================

echo "=== NAMESPACE ==="
kubectl get namespace voting-system

echo "=== ALL RESOURCES ==="
kubectl get all -n voting-system

echo "=== PERSISTENT VOLUMES ==="
kubectl get pv,pvc -n voting-system

echo "=== CONFIGMAPS ==="
kubectl get configmaps -n voting-system

echo "=== SECRETS ==="
kubectl get secrets -n voting-system

echo "=== HPA STATUS ==="
kubectl get hpa -n voting-system

echo "=== RESOURCE USAGE ==="
kubectl top pods -n voting-system

echo "=== NODE DISTRIBUTION ==="
kubectl get pods -n voting-system -o wide

echo "=== ENDPOINTS ==="
kubectl get endpoints -n voting-system

echo ""
echo "Access URLs:"
echo "  Blue Team:  http://<EC2_PUBLIC_IP>:30001"
echo "  Red Team:   http://<EC2_PUBLIC_IP>:30002"
echo "  Scoreboard: http://<EC2_PUBLIC_IP>:30003"
```

---

## 🧹 Cleanup Commands (End of Workshop)

```bash
# Delete all resources in namespace
kubectl delete all --all -n voting-system

# Delete ConfigMaps and Secrets
kubectl delete configmaps --all -n voting-system
kubectl delete secrets --all -n voting-system

# Delete HPAs
kubectl delete hpa --all -n voting-system

# Delete PVC (WARNING: deletes volume claim)
kubectl delete pvc --all -n voting-system

# Delete PV (if reclaim policy allows)
kubectl delete pv redis-pv

# Delete the entire namespace (removes EVERYTHING)
kubectl delete namespace voting-system

# Verify cleanup
kubectl get all -n voting-system
# Expected: "No resources found in voting-system namespace."
```

---

## 📣 The 5-Minute Standup — Day 3

> *Read this aloud to your team at end of day:*

```
✅ Day 3 Standup — Persistence, Configs & Scaling

• Created a Kubernetes Secret (redis-secret) for Redis password storage.
  Values are base64-encoded and injected via secretKeyRef — no plaintext
  passwords anywhere in our YAML or application code.

• Provisioned a 2Gi PersistentVolume and PersistentVolumeClaim using
  hostPath storage on Worker Node 01. Redis now survives pod restarts —
  votes persist even when pods are deleted and recreated.

• Deployed the Results Dashboard (port 30003) — a live auto-refreshing
  scoreboard showing Red vs. Blue vote counts with progress bars and
  a "LEADING" badge for the current winner.

• Installed metrics-server and applied HorizontalPodAutoscalers for both
  teams: scales from 2 to 8 replicas on CPU > 60%, with a 2-minute
  scale-down stabilization window to prevent flapping.

• Demonstrated zero-downtime rolling updates via 'kubectl set env'
  and verified rollback capability with 'kubectl rollout undo'.

• VoteVibe is now fully production-ready across all three EC2 nodes.

Final URLs:
  🔵 Blue Team:   http://<EC2_IP>:30001
  🔴 Red Team:    http://<EC2_IP>:30002
  🏆 Scoreboard:  http://<EC2_IP>:30003

Blockers: None.
Status: SHIPPED. 🚀
```

---
---

# 📚 Workshop Reference Card

## Quick kubectl Cheatsheet

| Command | Purpose |
|---|---|
| `kubectl apply -f <file>` | Create/update resources from YAML |
| `kubectl get all -n voting-system` | List all resources in namespace |
| `kubectl describe pod <name>` | Detailed pod info + events |
| `kubectl logs <pod> -f` | Stream logs |
| `kubectl exec -it <pod> -- bash` | Shell into pod |
| `kubectl rollout status deploy/<name>` | Watch rolling update |
| `kubectl rollout undo deploy/<name>` | Rollback deployment |
| `kubectl scale deploy/<name> --replicas=N` | Manual scale |
| `kubectl get hpa` | View autoscaler status |
| `kubectl top pods` | Resource usage |
| `kubectl delete ns voting-system` | Nuke everything |

## Architecture Summary

```
Internet
    │
    ▼
EC2 Public IP
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
              (Worker Node disk)
```

## K8s Concepts Covered — Full Map

| Concept | Object | Day |
|---|---|---|
| Resource isolation | Namespace | 1 |
| Running workloads | Deployment | 1 |
| Expose externally | NodePort Service | 1 |
| Rolling updates | Deployment strategy | 1 |
| Non-sensitive config | ConfigMap | 1 |
| Internal communication | ClusterIP Service | 2 |
| DNS-based discovery | Service DNS | 2 |
| Label routing | Selectors | 2 |
| Health checking | Liveness/Readiness Probes | 2 |
| Sensitive config | Secret | 3 |
| Persistent storage | PV + PVC | 3 |
| Autoscaling | HorizontalPodAutoscaler | 3 |
| Zero-downtime updates | Rolling update | 3 |
| Rollback | `kubectl rollout undo` | 3 |

---

> **🎉 Congratulations — VoteVibe is live!**
> *You've gone from zero to a fully orchestrated, persistent, auto-scaling Kubernetes application in 3 days. Sarah is pleased. The Red Team is winning. This is fine.*