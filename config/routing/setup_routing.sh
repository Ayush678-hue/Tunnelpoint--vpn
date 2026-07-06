#!/usr/bin/env bash
# TunnelPoint Advanced Linux Routing & VTI Interface Setup Script (PART 16)
# Configures kernel sysctl parameters, creates Virtual Tunnel Interfaces (vti0), and sets up Policy-Based Routing (PBR)

set -euo pipefail

# Identify Node Role (Gateway A vs Gateway B) based on hostname or environment variable
NODE_ROLE="${NODE_ROLE:-gateway-a}"

echo "===> [Step 1] Applying enterprise sysctl kernel hardening parameters..."
sysctl -p /config/routing/sysctl.conf || sysctl -w net.ipv4.ip_forward=1 net.ipv4.conf.all.rp_filter=1

echo "===> [Step 2] Configuring Route-Based Virtual Tunnel Interface (VTI / XFRM)..."
# Check if vti0 interface already exists; delete if rebuilding
ip link del vti0 2>/dev/null || true

if [ "${NODE_ROLE}" == "gateway-a" ]; then
    LOCAL_WAN="203.0.113.10"
    REMOTE_WAN="198.51.100.20"
    VTI_IP="10.255.255.1/30"
    REMOTE_LAN="192.168.20.0/24"
    LAN_DEV="eth1"
    WAN_DEV="eth0"
else
    LOCAL_WAN="198.51.100.20"
    REMOTE_WAN="203.0.113.10"
    VTI_IP="10.255.255.2/30"
    REMOTE_LAN="192.168.10.0/24"
    LAN_DEV="eth1"
    WAN_DEV="eth0"
fi

# Create VTI interface tied to our public WAN endpoints and XFRM mark 100!
# When packets are routed into vti0, kernel XFRM engine automatically applies Security Association matching fwmark 100!
ip link add vti0 type vti local "${LOCAL_WAN}" remote "${REMOTE_WAN}" key 100
ip addr add "${VTI_IP}" dev vti0
ip link set dev vti0 mtu 1400  # Enforce 1400 MTU to prevent IPsec fragmentation!
ip link set dev vti0 up

echo "     [SUCCESS] Virtual Tunnel Interface vti0 created and brought UP with IP ${VTI_IP}"

echo "===> [Step 3] Configuring Forwarding Information Base (FIB) Routing Tables..."
# Add static route directing all traffic for the remote office LAN into our virtual tunnel interface vti0!
ip route replace "${REMOTE_LAN}" dev vti0 metric 50

echo "     [SUCCESS] Static route added: ${REMOTE_LAN} via dev vti0"

echo "===> [Step 4] Configuring Policy-Based Routing (PBR / RPDB) via ip rule..."
# Ensure custom routing table exists in /etc/iproute2/rt_tables
if ! grep -q "100 vpn_table" /etc/iproute2/rt_tables 2>/dev/null; then
    echo "100 vpn_table" >> /etc/iproute2/rt_tables
fi

# Create custom route inside vpn_table
ip route replace "${REMOTE_LAN}" dev vti0 table vpn_table

# Create Policy Rule: Any traffic marked with fwmark 100 or originating from LAN must lookup vpn_table
ip rule del table vpn_table 2>/dev/null || true
ip rule add to "${REMOTE_LAN}" table vpn_table priority 10

echo "===> [SUCCESS] Advanced Linux routing and VTI interface configuration complete!"
ip route show
ip rule show
