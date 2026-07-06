# TunnelPoint Azure Cloud Infrastructure Blueprint (PART 22)
# Target File: /cloud/azure/main.tf
# Deploys Resource Group, VNet, GatewaySubnet, Public IP, Azure VNet Gateway, and IPsec Policy

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "location" {
  type    = string
  default = "East US"
}

variable "resource_group_name" {
  type    = string
  default = "tunnelpoint-rg"
}

variable "vnet_cidr" {
  type    = string
  default = "10.200.0.0/16"
}

variable "on_prem_gateway_ip" {
  type    = string
  default = "203.0.113.10"
}

variable "on_prem_lan_cidr" {
  type    = string
  default = "192.168.10.0/24"
}

# ==============================================================================
# 1. AZURE RESOURCE GROUP & VIRTUAL NETWORK
# ==========================================
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "tunnelpoint-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = [var.vnet_cidr]
}

# Azure strictly requires the VPN gateway subnet to be named 'GatewaySubnet'!
resource "azurerm_subnet" "gateway_subnet" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.200.255.0/24"]
}

resource "azurerm_public_ip" "vpngw_pip" {
  name                = "tunnelpoint-vpngw-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# ==============================================================================
# 2. AZURE VIRTUAL NETWORK GATEWAY (IPSEC / IKEV2)
# ==========================================
resource "azurerm_virtual_network_gateway" "vpngw" {
  name                = "tunnelpoint-azure-vpngw"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  active_active       = false
  enable_bgp          = false
  sku                 = "VpnGw2"

  ip_configuration {
    name                          = "vpngw-ipconf"
    public_ip_address_id          = azurerm_public_ip.vpngw_pip.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway_subnet.id
  }
}

# ==============================================================================
# 3. LOCAL NETWORK GATEWAY (ON-PREMISE TUNNELPOINT GATEWAY ENDPOINT)
# ==========================================
resource "azurerm_local_network_gateway" "local_gw" {
  name                = "tunnelpoint-onprem-localgw"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  gateway_address     = var.on_prem_gateway_ip
  address_space       = [var.on_prem_lan_cidr]
}

# ==============================================================================
# 4. AZURE IPSEC SITE-TO-SITE CONNECTION & CUSTOM CRYPTOGRAPHIC POLICY
# ==========================================
resource "azurerm_virtual_network_gateway_connection" "s2s_conn" {
  name                = "tunnelpoint-azure-connection"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  type                       = "IPsec"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.vpngw.id
  local_network_gateway_id   = azurerm_local_network_gateway.local_gw.id

  # Enforce custom high-security IPsec policy matching our StrongSwan swanctl.conf!
  ipsec_policy {
    ike_encryption   = "AES256"
    ike_integrity    = "SHA384"
    dh_group         = "ECP384" # DH Group 20
    ipsec_encryption = "GCMAES256"
    ipsec_integrity  = "GCMAES256"
    pfs_group        = "ECP384" # PFS Group 20
    sa_lifetime      = 3600
  }
}

output "azure_vpngw_public_ip" {
  value       = azurerm_public_ip.vpngw_pip.ip_address
  description = "Public WAN IP of Azure Virtual Network Gateway"
}
