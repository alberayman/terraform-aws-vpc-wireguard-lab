variable "region" {
  description = "AWS region for all resources."
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Prefix applied to the Name tag of every resource."
  type        = string
  default     = "vpc-demo"
}

variable "mac_public_key" {
  description = "WireGuard public key of the client peer. Generate locally with: wg genkey | tee privatekey | wg pubkey > publickey"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Local filesystem path to the SSH public key uploaded as the EC2 key pair. Supports ~ expansion."
  type        = string
  default     = "~/.ssh/vpc-demo-key.pub"
}

variable "nginx_instance_type" {
  description = "EC2 instance type for the NGINX server."
  type        = string
  default     = "t2.micro"
}

variable "wireguard_instance_type" {
  description = "EC2 instance type for the WireGuard VPN server."
  type        = string
  default     = "t2.micro"
}
