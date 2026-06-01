# AWS VPC + WireGuard VPN — Terraform

> Provisions a production-style AWS VPC in `eu-west-1` with an NGINX web server isolated in a private subnet and a WireGuard VPN server as the **only** network entry point.
> The NGINX instance has no public IP and is unreachable from the internet — access is exclusively through the authenticated VPN tunnel.

---

## Architecture

```
                 ┌─────────────────────────────────────────────────────────────┐
                 │                        AWS  eu-west-1                        │
                 │                                                               │
                 │  ┌──────────────────── VPC  10.0.0.0/16 ──────────────────┐ │
                 │  │                                                           │ │
                 │  │  ┌─────────────── PUBLIC SUBNETS ─────────────────────┐  │ │
                 │  │  │  10.0.0.0/24 · 10.0.1.0/24 · 10.0.2.0/24          │  │ │
                 │  │  │  eu-west-1a   ·  eu-west-1b  ·  eu-west-1c         │  │ │
                 │  │  │                                                      │  │ │
                 │  │  │   ┌────────────────────┐   ┌───────────────────┐   │  │ │
                 │  │  │   │  WireGuard Server   │   │   NAT Gateway     │   │  │ │
                 │  │  │   │  EC2  (eu-west-1a)  │   │   + EIP           │   │  │ │
                 │  │  │   │  UDP :51820         │   │   (eu-west-1a)    │   │  │ │
                 │  │  │   │  source_dest=false  │   └─────────┬─────────┘   │  │ │
                 │  │  │   └──────────┬──────────┘             │             │  │ │
                 │  │  └─────────────│────────────────────────│─────────────┘  │ │
                 │  │                │  VPC-local route        │ outbound only  │ │
                 │  │  ┌─────────────│────── PRIVATE SUBNETS ──│──────────────┐ │ │
                 │  │  │  10.0.10.0/24 · 10.0.11.0/24 · 10.0.12.0/24         │ │ │
                 │  │  │  eu-west-1a    ·   eu-west-1b  ·   eu-west-1c        │ │ │
                 │  │  │             │                                         │ │ │
                 │  │  │   ┌─────────▼──────────┐                             │ │ │
                 │  │  │   │    NGINX  EC2       │                             │ │ │
                 │  │  │   │    (eu-west-1a)     │                             │ │ │
                 │  │  │   │    Docker · :80     │                             │ │ │
                 │  │  │   │    no public IP     │                             │ │ │
                 │  │  │   └────────────────────-┘                             │ │ │
                 │  │  └─────────────────────────────────────────────────────┘ │ │
                 │  └─────────────────────────────────────────────────────────── │
                 └─────────────────────────────────────────────────────────────────┘
```

---

## Traffic Flow

```
Your Laptop (macOS)
      │
      │  WireGuard UDP/51820  (encrypted tunnel)
      ▼
Internet Gateway
      │
      ▼
WireGuard Server  —  public subnet  —  10.0.0.x / <public-ip>
      │   Decrypts tunnel, applies iptables MASQUERADE
      │   (rewrites src → WireGuard private IP so return traffic routes back)
      │   Forwards packet via VPC local route
      ▼
NGINX EC2  —  private subnet  —  10.0.10.x:80
      │
      │  Outbound internet (yum, docker pull) via NAT Gateway
      ▼
Internet
```

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| [Terraform](https://developer.hashicorp.com/terraform/downloads) | >= 1.5 | `brew tap hashicorp/tap && brew install hashicorp/tap/terraform` |
| [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) | >= 2.0 | `brew install awscli` |
| [WireGuard tools](https://www.wireguard.com/install/) | any | `brew install wireguard-tools` |
| An AWS account with IAM permissions to create VPC, EC2, and EIP resources | — | — |

Configure the AWS CLI before running Terraform:

```bash
aws configure
# Enter: Access Key ID, Secret Access Key, region (eu-west-1), output format (json)
```

---

## Project Structure

```
.
├── main.tf                   # All AWS resources (VPC, subnets, IGW, NAT GW, EC2, SGs)
├── variables.tf              # Input variables with types, defaults, and descriptions
├── outputs.tf                # Stack outputs (NGINX private IP, WireGuard public IP)
├── providers.tf              # AWS provider + Terraform version constraints
├── terraform.tfvars.example  # Template — copy to terraform.tfvars and fill in values
├── .gitignore                # Excludes state, secrets, .tfvars, and generated files
├── README.md                 # This file
└── CONTRIBUTING.md           # Guide for extending the project
```

---

## Usage

### 1 — Generate an SSH key pair

```bash
ssh-keygen -t ed25519 -f ~/.ssh/vpc-demo-key -C "vpc-demo"
```

The default value of `ssh_public_key_path` points to `~/.ssh/vpc-demo-key.pub`.
If you use a different path, override the variable in `terraform.tfvars`.

> Keep `~/.ssh/vpc-demo-key` (the private key) secret. Never commit it.

---

### 2 — Generate WireGuard client keys

```bash
mkdir -p ~/.wireguard
wg genkey | tee ~/.wireguard/mac-private.key | wg pubkey > ~/.wireguard/mac-public.key
chmod 600 ~/.wireguard/mac-private.key

# Copy the public key — you will paste it into terraform.tfvars
cat ~/.wireguard/mac-public.key
```

---

### 3 — Configure variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Open `terraform.tfvars` and set `mac_public_key` to the output of the previous step.
All other variables have sensible defaults; adjust as needed.

---

### 4 — Deploy infrastructure

```bash
terraform init      # Download the AWS provider plugin
terraform plan      # Preview what will be created (22 resources)
terraform apply     # Create the resources (~3 minutes)
```

After `apply` completes, Terraform prints the outputs:

```
nginx_private_ip    = "10.0.10.x"
wireguard_public_ip = "x.x.x.x"
```

> The NAT Gateway takes ~60 seconds to become available after creation.
> Both EC2 instances run their `user_data` bootstrap scripts on first boot (~2 minutes).

---

### 5 — Retrieve the WireGuard server public key

The WireGuard server generates its own key pair on first boot.
After the instance status checks pass (~2 minutes), fetch the public key:

```bash
ssh -i ~/.ssh/vpc-demo-key ec2-user@$(terraform output -raw wireguard_public_ip) \
  "sudo cat /etc/wireguard/server-public.key"
```

Copy the output — you need it for the client configuration in the next step.

---

### 6 — Configure the WireGuard client (macOS)

Create the client configuration file:

```bash
sudo mkdir -p /etc/wireguard
sudo tee /etc/wireguard/wg0.conf > /dev/null <<EOF
[Interface]
PrivateKey = $(cat ~/.wireguard/mac-private.key)
Address = 10.8.0.2/24

[Peer]
PublicKey = <paste server public key from step 5>
Endpoint = $(terraform output -raw wireguard_public_ip):51820
AllowedIPs = 10.0.10.0/24
PersistentKeepalive = 25
EOF
sudo chmod 600 /etc/wireguard/wg0.conf
```

`AllowedIPs = 10.0.10.0/24` creates a **split-tunnel** — only traffic destined for the private subnet is routed through the VPN. Change to `0.0.0.0/0` for a full tunnel.

Bring the tunnel up:

```bash
sudo wg-quick up wg0
```

Confirm the tunnel is active:

```bash
sudo wg show
```

---

### 7 — Verify NGINX is reachable

```bash
curl http://$(terraform output -raw nginx_private_ip)
```

You should receive the default NGINX welcome page HTML. Tear down the tunnel and try again — the address becomes unreachable without VPN:

```bash
sudo wg-quick down wg0
curl http://$(terraform output -raw nginx_private_ip)   # should time out
```

---

## Variables Reference

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `region` | `string` | `"eu-west-1"` | No | AWS region for all resources. |
| `project_name` | `string` | `"vpc-demo"` | No | Prefix applied to the `Name` tag of every resource. |
| `mac_public_key` | `string` | — | **Yes** | WireGuard public key of the client peer. |
| `ssh_public_key_path` | `string` | `"~/.ssh/vpc-demo-key.pub"` | No | Local path to the SSH public key uploaded as the EC2 key pair. Supports `~` expansion. |
| `nginx_instance_type` | `string` | `"t2.micro"` | No | EC2 instance type for the NGINX server. |
| `wireguard_instance_type` | `string` | `"t2.micro"` | No | EC2 instance type for the WireGuard VPN server. |

---

## Outputs Reference

| Name | Description |
|------|-------------|
| `nginx_private_ip` | Private IP address of the NGINX EC2 instance. Reachable only via the WireGuard tunnel. |
| `wireguard_public_ip` | Public IP address of the WireGuard VPN server. Use as the `Endpoint` in the client config. |

---

## Security Design Decisions

| Decision | Rationale |
|----------|-----------|
| **NGINX in a private subnet** | The web server has no public IP and no route from the internet. The only network path to port 80 is through the VPN tunnel. |
| **WireGuard as the sole entry point** | Port 51820/UDP is the only public port. SSH (22/TCP) is also open on the WireGuard security group for initial key retrieval — restrict this to a known CIDR in production (`var.admin_cidr_block`). |
| **`source_dest_check = false`** | AWS drops packets whose source or destination IP does not match the instance's own IP. Disabling this allows the WireGuard server to act as a router and forward decrypted VPN packets to the private subnet on behalf of VPN clients (10.8.0.x). |
| **`iptables MASQUERADE`** | The WireGuard server rewrites the source IP of forwarded packets to its own private VPC IP. Without this, the NGINX server would try to reply directly to 10.8.0.2, a CIDR the VPC has no route for, and the response would be dropped. |
| **NAT Gateway for private subnet egress** | NGINX can reach the internet (for `yum update`, `docker pull`) without ever having a public IP. Outbound traffic exits via the NAT Gateway, keeping the instance fully private. |
| **Security group principle of least privilege** | The NGINX security group allows HTTP and SSH only from `10.0.0.0/16` (the VPC CIDR). No traffic from outside the VPC can reach port 80 or 22 on NGINX, regardless of routing. |

---

## Cost Warning

The following resources incur charges even when no traffic flows. **Destroy the stack when it is no longer needed.**

| Resource | Approximate cost (us-east-1 / eu-west-1) |
|----------|------------------------------------------|
| NAT Gateway — hourly | ~$0.045 / hr (~$32 / month) |
| NAT Gateway — data processing | ~$0.045 / GB |
| Elastic IP (EIP) on NAT GW | ~$0.005 / hr when attached |
| WireGuard EC2 (`t2.micro`) | Free tier eligible; ~$0.013 / hr otherwise |
| NGINX EC2 (`t2.micro`) | Free tier eligible; ~$0.013 / hr otherwise |

> At default settings, the minimum idle cost is approximately **$35–40 / month** driven primarily by the NAT Gateway.

---

## Cleanup

Remove all resources managed by this configuration:

```bash
terraform destroy
```

Terraform resolves the dependency graph and tears down resources in the correct order: EC2 instances → security groups → NAT Gateway → EIP → route tables → subnets → IGW → VPC.

Remove the local WireGuard tunnel config after destroying:

```bash
sudo wg-quick down wg0 2>/dev/null; sudo rm -f /etc/wireguard/wg0.conf
```

---

## Portfolio / Learning Notes

This project is designed as a hands-on demonstration of the following skills:

| Skill | Where demonstrated |
|-------|--------------------|
| **Multi-AZ VPC design** | 3 public + 3 private subnets spread across 3 AZs with independent route tables |
| **NAT Gateway pattern** | Private instances reach the internet for bootstrap without a public IP |
| **Terraform data sources** | `aws_availability_zones` and `aws_ami` resolved dynamically — no hardcoded AZ names or AMI IDs |
| **EC2 user_data bootstrapping** | Both instances self-configure on first boot without an external config management tool |
| **WireGuard as a VPN gateway** | Modern, lightweight VPN (faster handshake and smaller attack surface than OpenVPN / IPSec) used as the sole entry point |
| **iptables IP masquerading** | Enables the VPN server to forward traffic to private resources while maintaining correct TCP return-path routing |
| **`source_dest_check = false`** | Overrides AWS's default packet-drop behaviour to allow EC2 to act as a router |
| **Security group segmentation** | NGINX rejects all traffic that did not originate inside the VPC CIDR |
| **Terraform count meta-argument** | Subnets, route table associations created with a single resource block |
| **Structured Terraform outputs** | Outputs feed downstream shell commands without re-querying the AWS API |
