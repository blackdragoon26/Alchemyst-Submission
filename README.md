# iii Quickstart — AWS Distributed Deployment
### DevOps Internship Assignment Submission

---

## Architecture

```
                          ┌──────────────────────────────────────────────────────────┐
                          │  AWS VPC  10.0.0.0/16  (eu-north-1)                     │
                          │                                                          │
  Internet                │  ┌──────────────────────────────────────────────────┐   │
     │                    │  │  Public subnet  10.0.1.0/24                      │   │
     │  HTTP :80          │  │                                                  │   │
     ▼                    │  │   ┌──────────────────────────────────────────┐   │   │
  ┌──────────────┐        │  │   │  Gateway VM  (Elastic IP: 16.192.37.39)  │   │   │
  │   Your curl  │───────►│  │   │  nginx reverse proxy → engine:3111       │   │   │
  └──────────────┘        │  │   └──────────────────┬───────────────────────┘   │   │
                          │  └─────────────────────-│────────────────────────────┘   │
                          │                         │ HTTP :3111                     │
                          │  ┌──────────────────────▼───────────────────────────┐   │
                          │  │  Private subnet  10.0.2.0/24                     │   │
                          │  │  (no inbound from internet)                      │   │
                          │  │                                                  │   │
                          │  │   ┌──────────────────────────────────────────┐   │   │
                          │  │   │  Engine VM  (10.0.2.64)                  │   │   │
                          │  │   │  iii engine                              │   │   │
                          │  │   │  :49134  WebSocket (worker RPC)          │   │   │
                          │  │   │  :3111   HTTP API                        │   │   │
                          │  │   └────────────┬──────────────┬─────────────┘   │   │
                          │  │                │  WS :49134   │  WS :49134      │   │
                          │  │   ┌────────────▼──┐   ┌───────▼───────────┐    │   │
                          │  │   │ Math Worker   │   │  Caller Worker    │    │   │
                          │  │   │ (10.0.2.211)  │   │  (10.0.2.82)      │    │   │
                          │  │   │ Python        │   │  TypeScript       │    │   │
                          │  │   │ math::add     │   │  math::add_two_   │    │   │
                          │  │   │               │   │  numbers          │    │   │
                          │  │   │               │   │  http::add_two_   │    │   │
                          │  │   └───────────────┘   │  numbers (HTTP)   │    │   │
                          │  │                        └───────────────────┘    │   │
                          │  └──────────────────────────────────────────────────┘   │
                          └──────────────────────────────────────────────────────────┘
```

### RPC flow for a single request

```
curl POST /math/add-two-numbers
  → nginx (Gateway VM, public)          # only public-facing entry point
  → iii engine HTTP :3111 (private)     # routes the request
  → caller-worker via WebSocket RPC     # TypeScript, calls math::add
  → math-worker via WebSocket RPC       # Python, does the addition
  → state worker (in engine)            # persists running total
  → result flows back → JSON response
```

---

## API Reference

### `POST /math/add-two-numbers`

**Request body:**

```json
{ "a": 10, "b": 20 }
```

**Response body:**

```json
{ "c": 30, "running_total": 30 }
```

| Field | Type | Description |
|-------|------|-------------|
| `a` | number | First operand |
| `b` | number | Second operand |
| `c` | number | Sum of a + b |
| `running_total` | number | Cumulative sum across all calls since engine start |

**Live example:**

<img width="1470" height="956" alt="Screenshot 2026-05-21 at 1 16 26 AM" src="https://github.com/user-attachments/assets/bdfcc553-1e58-4696-bf57-0e350a7085e4" />

---

## Infrastructure

4 EC2 `t3.micro` instances (free-tier eligible in eu-north-1), all in the same VPC:

| VM | Subnet | Public IP | Role |
|----|--------|-----------|------|
| gateway | public (10.0.1.0/24) | 16.192.37.39 (Elastic IP) | nginx reverse proxy |
| engine | private (10.0.2.0/24) | none | iii engine (WebSocket broker + HTTP API) |
| math-worker | private (10.0.2.0/24) | none | Python worker — `math::add` |
| caller-worker | private (10.0.2.0/24) | none | TypeScript worker — `math::add_two_numbers` + HTTP trigger |

**Network hygiene:** The private subnet VMs have no public IP and no inbound security group rules from the internet. Only the gateway's port 80 is publicly reachable. Worker VMs can only be SSH'd into via the gateway as a bastion. Private VMs reach the internet for package installs via a NAT gateway (outbound only).

**Security groups:**
- `gateway-sg`: inbound 80 (0.0.0.0/0), 22 (0.0.0.0/0)
- `engine-sg`: inbound 49134 + 3111 from VPC CIDR only, 22 from gateway-sg only
- `workers-sg`: inbound 22 from gateway-sg only

---

## Prerequisites (fresh account)

- [Terraform](https://developer.hashicorp.com/terraform/install) ≥ 1.6
- [AWS CLI](https://aws.amazon.com/cli/) configured (`aws configure`)
- An EC2 key pair in your target region — create one in the AWS console under **EC2 → Key Pairs → Create**, download the `.pem` file

```bash
chmod 400 ~/.ssh/your-key.pem
ssh-add ~/.ssh/your-key.pem   # needed for SSH agent forwarding to private VMs
```

---

## Deploy from scratch

### 1. Clone and configure

```bash
git clone https://github.com/blackdragoon26/Alchemyst-Submission.git
cd Alchemyst-Submission/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region    = "eu-north-1"
key_pair_name = "your-key-name"    # name in AWS, without .pem
ami_id        = "ami-0826f7fac3eaaa32a"   # Ubuntu 22.04 LTS, eu-north-1
instance_type = "t3.micro"         # free-tier eligible in eu-north-1
```

> **AMI note:** AMI IDs are region-specific. If you deploy to a different region, find the correct Ubuntu 22.04 LTS amd64 AMI for that region:
> ```bash
> aws ec2 describe-images --region YOUR_REGION --owners 099720109477 \
>   --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
>             "Name=state,Values=available" "Name=architecture,Values=x86_64" \
>   --query "sort_by(Images, &CreationDate)[-1].ImageId" --output text
> ```

> **Instance type note:** `t2.micro` is free-tier in US regions. `t3.micro` is free-tier in eu-north-1. Run this to check your region:
> ```bash
> aws ec2 describe-instance-types --region YOUR_REGION \
>   --filters "Name=free-tier-eligible,Values=true" \
>   --query "InstanceTypes[*].InstanceType" --output table
> ```

### 2. Provision infrastructure

```bash
terraform init
terraform plan    # review what will be created
terraform apply   # type 'yes' when prompted (~4 minutes)
```

Terraform will print the gateway public IP and all private IPs when done.

### 3. Wait for bootstrap

The VMs run their setup scripts automatically via `user_data` after Terraform finishes. Allow **5-7 minutes** for all services to start. The engine VM takes longest (installs `iii`, scaffolds the project, starts the service).

### 4. Verify and test

```bash
# Gateway health check
curl http://GATEWAY_IP/healthz
# → ok

# Full end-to-end inference call
curl -X POST http://GATEWAY_IP/math/add-two-numbers \
  -H 'Content-Type: application/json' \
  -d '{"a": 10, "b": 20}'
# → {"c":30,"running_total":30}
```

### 5. Tear down

```bash
terraform destroy   # type 'yes' — removes all AWS resources
```

---

## SSH access for debugging

Private VMs have no public IP. Use the gateway as a bastion:

```bash
# SSH to gateway
ssh -i ~/.ssh/your-key.pem ubuntu@GATEWAY_IP

# SSH to any private VM (agent forwarding required — see Prerequisites)
ssh -A -i ~/.ssh/your-key.pem -J ubuntu@GATEWAY_IP ubuntu@PRIVATE_IP

# Check engine logs
sudo journalctl -u iii-engine -f

# Check math-worker logs
sudo journalctl -u iii-math-worker -f

# Check caller-worker logs
sudo journalctl -u iii-caller-worker -f

# Check what's listening on engine VM
ss -tlnp | grep -E '3111|49134'
```

---

## Troubleshooting (lessons from actual deployment)

These are real issues encountered during deployment of this exact stack.

**502 Bad Gateway from nginx**
The iii engine's HTTP server binds to `127.0.0.1:3111` by default. The `config.yaml` must explicitly set `host: 0.0.0.0` under the `iii-http` worker config. This is already done in `scripts/setup_engine.sh`.

**`couldn't find resource` when creating EC2 instances**
Two causes: (1) wrong AMI ID for the region — AMI IDs are not global, get the correct one with the command above; (2) instance type not free-tier eligible in the region — `t2.micro` is US-only, use `t3.micro` in eu-north-1.

**iii installer fails with `jq is required`**
The iii install script requires `jq` but Ubuntu 22.04 doesn't ship it. `apt-get install -y jq` must come before the iii install. Fixed in `setup_engine.sh`.

**iii installed to wrong path**
The installer puts binaries in `/home/ubuntu/.local/bin/` when run as the ubuntu user, not `/root/.local/bin/`. The setup scripts copy binaries to `/usr/local/bin/` so systemd (running as ubuntu) can find them.

**Wrong Python SDK package**
The PyPI package named `iii` is a completely unrelated old package. The correct package is `iii-sdk==0.11.0`.

**TypeScript worker fails to start**
The quickstart project uses ES modules (`"type": "module"` in package.json). It requires `tsx` as the runner, not `ts-node`. The correct ExecStart is `/usr/bin/node --import tsx/esm src/worker.ts`.

**nginx syntax error on proxy_pass**
Shell heredoc escaping adds a backslash before semicolons in some contexts, producing `proxy_pass http://IP:3111\;` which breaks nginx. Fixed in `setup_gateway.sh` by careful heredoc quoting.

**SSH to private VMs denied**
The `-J` jump flag alone doesn't forward your local key to the private VM. Use `-A` (agent forwarding) and add the key to your local SSH agent with `ssh-add ~/.ssh/your-key.pem` first.

---

## Production hardening

**What I would do before this goes anywhere near production:**

1. **Restrict SSH access.** The gateway currently allows SSH from `0.0.0.0/0`. Replace this with your VPN or office CIDR, or eliminate inbound SSH entirely by switching to AWS Systems Manager Session Manager — no open port 22 needed at all.

2. **TLS everywhere.** Put the gateway behind an Application Load Balancer with an ACM certificate. Redirect HTTP to HTTPS. The iii engine's WebSocket connections between workers should also be encrypted — either via a VPN between private VMs (WireGuard) or by adding a private CA.

3. **Secrets management.** Any credentials (API keys, database passwords) the workers need should come from AWS Secrets Manager injected at runtime via IAM instance roles, not hardcoded in user_data scripts which are visible in the EC2 console.

4. **Least-privilege IAM.** Each EC2 instance should have its own IAM role with only the permissions it actually needs. Currently the instances have no IAM role at all.

5. **Structured logging and alerting.** Pipe all systemd journal output to CloudWatch Logs. Add CloudWatch alarms on the engine and worker services so failures page someone instead of silently returning 502s.

6. **Immutable deployments.** Bake the worker code and all dependencies into an AMI using Packer. Deployments become an Auto Scaling Group rolling update rather than running install scripts on a live box. This eliminates the entire class of bugs we hit during setup (wrong package names, missing jq, path issues).

7. **Health checks.** The gateway is a single point of failure. Put it behind an ALB with a health check on `/healthz`. Add a `/health` endpoint to the engine that verifies workers are connected before returning 200.

---

## What I'd do differently at 100× model size

1. **GPU instances.** A model 100× larger needs at minimum a `g4dn.xlarge` (NVIDIA T4) or `g5.xlarge` (A10G). The model VM moves to its own GPU-optimised AMI (AWS Deep Learning AMI) in its own subnet with no internet exposure.

2. **Dedicated inference server.** Replace the in-process Python worker with a proper inference server — vLLM, Text Generation Inference (TGI), or TensorRT-LLM. These handle continuous batching, paged KV-cache, and quantisation. The iii worker becomes a thin adapter that calls the inference server over HTTP/gRPC locally.

3. **Model storage.** A 100× model won't fit in a root EBS volume. Mount it from S3 at startup using `s5cmd` (fast parallel downloader), or pre-bake it into an EBS snapshot that is attached to every inference instance. Cold start time becomes a key metric.

4. **Horizontal scaling with a request queue.** Replace direct WebSocket RPC with an SQS queue in front of the inference worker. The gateway enqueues requests; one or more inference workers poll and process. This decouples the gateway from the inference backend, absorbs traffic spikes, and makes retries cheap. Auto Scaling can add inference instances based on queue depth.

5. **Spot instances.** Inference is stateless and tolerates interruption. Use EC2 Spot Instances (up to 90% cheaper than on-demand) with an on-demand fallback in the Auto Scaling Group.

6. **Observability.** Add Prometheus metrics (iii exposes them on port 9464), scrape with Amazon Managed Prometheus, visualise in Grafana. Track p50/p95/p99 inference latency, queue depth, GPU utilisation, and KV-cache hit rate in one dashboard.

7. **Multi-AZ.** Spread inference instances across availability zones. The current single-AZ setup means one AZ failure takes everything down.
