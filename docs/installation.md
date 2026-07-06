# TunnelPoint Installation & Verification Guide (PART 13)

This document contains the step-by-step installation instructions for setting up the required packages on Ubuntu Server 24.04 LTS, Debian 12, or within our custom Docker container lab.

For full architectural context and system diagrams, please reference [architecture.md](file:///C:/Users/ayush/.gemini/antigravity/scratch/tunnelpoint/docs/architecture.md).

## Quick-Start One-Line Installation Script
Run the following script on your bare-metal Linux server or VM to install all required StrongSwan, iptables, nftables, and diagnostic packages:

```bash
sudo apt-get update -y && sudo apt-get install -y --no-install-recommends \
    strongswan strongswan-pki libcharon-extra-plugins libcharon-extauth-plugins \
    libstrongswan-standard-plugins iproute2 iptables iptables-persistent nftables \
    ethtool conntrack tcpdump tshark iputils-ping traceroute mtr-tiny curl wget \
    iperf3 prometheus-node-exporter python3 python3-pip python3-vici
```

## Verifying StrongSwan Daemon Status
Once installed, verify that the modern `charon-systemd` or `strongswan-starter` daemon is operational:
```bash
# Check systemd service status
sudo systemctl status strongswan-starter || sudo systemctl status strongswan

# Check loaded cryptographic plugins via swanctl
sudo swanctl --stats
```
