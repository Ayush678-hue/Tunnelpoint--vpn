#!/usr/bin/env bash
# TunnelPoint Production Gateway Automated Deployment Script (PART 24)
# Target File: /scripts/deploy.sh
# Installs dependencies, applies hardening sysctl/iptables, configures StrongSwan VICI, and starts daemon

set -euo pipefail

# Must run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "[ERROR] This deployment script must be run as root or with sudo!" >&2
    exit 1
fi

NODE_ROLE="${1:-gateway-a}"
echo "=============================================================================="
echo "    TUNNELPOINT ENTERPRISE GATEWAY AUTOMATED DEPLOYMENT (${NODE_ROLE})        "
echo "=============================================================================="

echo "===> [Step 1] Updating system package repositories and installing core dependencies..."
apt-get update -y
apt-get install -y --no-install-recommends \
    strongswan \
    strongswan-pki \
    libcharon-extra-plugins \
    iproute2 \
    iptables \
    iptables-persistent \
    nftables \
    ethtool \
    conntrack \
    tcpdump \
    python3 \
    python3-pip \
    python3-vici \
    chrony

echo "===> [Step 2] Establishing secure directory hierarchy and permissions..."
mkdir -p /etc/swanctl/{x509,x509ca,private,conf.d}
chmod 700 /etc/swanctl/private
touch /var/log/strongswan.log
chmod 666 /var/log/strongswan.log

echo "===> [Step 3] Deploying master StrongSwan and VICI configuration files..."
cp /config/strongswan.conf /etc/strongswan.conf
cp "/config/${NODE_ROLE}/swanctl.conf" /etc/swanctl/swanctl.conf

echo "===> [Step 4] Deploying PKI certificates and RSA/ECDSA private keys..."
cp "/pki/build/certs/${NODE_ROLE}.crt" /etc/swanctl/x509/
cp "/pki/build/cacerts/ca-chain.crt" /etc/swanctl/x509ca/
cp "/pki/build/private/${NODE_ROLE}.key" /etc/swanctl/private/
chmod 600 /etc/swanctl/private/*

echo "===> [Step 5] Applying Linux kernel sysctl hardening and network routing rules..."
bash /config/routing/setup_routing.sh

echo "===> [Step 6] Applying zero-trust perimeter iptables firewall & NAT exemption rules..."
bash /config/firewall/iptables.rules

echo "===> [Step 7] Enabling and restarting StrongSwan systemd daemon..."
systemctl enable strongswan-starter || systemctl enable strongswan
systemctl restart strongswan-starter || systemctl restart strongswan

sleep 3
echo "===> [Step 8] Loading VICI configuration into charon and initiating IPsec tunnel..."
swanctl --load-all
if [ "${NODE_ROLE}" == "gateway-a" ]; then
    swanctl --initiate --child net-a-to-net-b || true
fi

echo "=============================================================================="
echo "    [SUCCESS] TUNNELPOINT GATEWAY DEPLOYMENT SUCCESSFULLY COMPLETED!          "
echo "=============================================================================="
swanctl --list-sas
