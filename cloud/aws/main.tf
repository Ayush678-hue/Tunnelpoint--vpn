# TunnelPoint AWS Cloud Infrastructure Blueprint (PART 22)
# Target File: /cloud/aws/main.tf
# Deploys VPC, Subnets, Security Groups, EC2 Gateway Instance, AWS Customer Gateway, and Site-to-Site VPN

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.100.0.0/16"
}

variable "on_prem_gateway_ip" {
  type        = string
  description = "Public WAN IP of on-premise TunnelPoint gateway (e.g. Gateway A)"
  default     = "203.0.113.10"
}

variable "on_prem_lan_cidr" {
  type        = string
  description = "Internal LAN subnet of on-premise network"
  default     = "192.168.10.0/24"
}

# ==============================================================================
# 1. AWS VIRTUAL PRIVATE CLOUD (VPC) & ROUTING
# ==========================================
resource "aws_vpc" "tunnelpoint_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "tunnelpoint-aws-vpc"
    Environment = "Production"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.tunnelpoint_vpc.id
  tags = { Name = "tunnelpoint-igw" }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.tunnelpoint_vpc.id
  cidr_block              = "10.100.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a"
  tags = { Name = "tunnelpoint-public-subnet" }
}

resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.tunnelpoint_vpc.id
  cidr_block        = "10.100.2.0/24"
  availability_zone = "${var.aws_region}a"
  tags = { Name = "tunnelpoint-private-subnet" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.tunnelpoint_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "tunnelpoint-public-rt" }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# ==============================================================================
# 2. SECURITY GROUP FOR STRONGSWAN / IPSEC GATEWAY
# ==========================================
resource "aws_security_group" "vpn_sg" {
  name        = "tunnelpoint-vpn-sg"
  description = "Allow IKEv2, NAT-T, ESP, and ICMP for TunnelPoint VPN"
  vpc_id      = aws_vpc.tunnelpoint_vpc.id

  # IKEv2 Key Exchange Handshake
  ingress {
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = [var.on_prem_gateway_ip]
  }

  # IPsec NAT Traversal (NAT-T)
  ingress {
    from_port   = 4500
    to_port     = 4500
    protocol    = "udp"
    cidr_blocks = [var.on_prem_gateway_ip]
  }

  # Raw Encapsulating Security Payload (ESP - IP Proto 50)
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "50"
    cidr_blocks = [var.on_prem_gateway_ip]
  }

  # Allow Internal LAN Cross-Forwarding
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.on_prem_lan_cidr, var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "tunnelpoint-vpn-sg" }
}

# ==============================================================================
# 3. AWS MANAGED SITE-TO-SITE VPN GATEWAY & CUSTOMER GATEWAY
# ==========================================
resource "aws_vpn_gateway" "vgw" {
  vpc_id = aws_vpc.tunnelpoint_vpc.id
  tags   = { Name = "tunnelpoint-aws-vgw" }
}

resource "aws_customer_gateway" "cgw" {
  bgp_asn    = 65000
  ip_address = var.on_prem_gateway_ip
  type       = "ipsec.1"
  tags       = { Name = "tunnelpoint-onprem-cgw" }
}

resource "aws_vpn_connection" "s2s_vpn" {
  vpn_gateway_id      = aws_vpn_gateway.vgw.id
  customer_gateway_id = aws_customer_gateway.cgw.id
  type                = "ipsec.1"
  static_routes_only  = true

  # Enforce AES-256-GCM and SHA-384 tunnel options
  tunnel1_ike_versions = ["ikev2"]
  tunnel1_phase1_encryption_algorithms = ["AES256-GCM-16"]
  tunnel1_phase1_integrity_algorithms  = ["SHA384"]
  tunnel1_phase1_dh_group_numbers      = [20] # ECP_384
  tunnel1_phase2_encryption_algorithms = ["AES256-GCM-16"]
  tunnel1_phase2_integrity_algorithms  = ["SHA384"]
  tunnel1_phase2_dh_group_numbers      = [20] # ECP_384 PFS

  tags = { Name = "tunnelpoint-aws-s2s-connection" }
}

resource "aws_vpn_connection_route" "on_prem_route" {
  destination_cidr_block = var.on_prem_lan_cidr
  vpn_connection_id      = aws_vpn_connection.s2s_vpn.id
}

output "aws_vpn_tunnel1_address" {
  value       = aws_vpn_connection.s2s_vpn.tunnel1_address
  description = "Public WAN IP of AWS Tunnel 1 endpoint"
}
