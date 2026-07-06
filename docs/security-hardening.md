# PART 20 — Enterprise Security Hardening Guide & Checklist

This document establishes the mandatory security hardening baseline for bare-metal and cloud Linux gateways deployed in the **TunnelPoint** architecture. A VPN gateway sits at the absolute perimeter of an enterprise network; compromising the gateway grants an adversary full access to both the public Internet and the internal corporate LAN.

---

## Table of Contents
1. [Operating System & Kernel Hardening](#1-operating-system--kernel-hardening)
2. [Cryptographic Hardening & FIPS 140-2 Compliance](#2-cryptographic-hardening--fips-140-2-compliance)
3. [PKI & Key Management Lifecycle](#3-pki--key-management-lifecycle)
4. [Perimeter Firewall & DDoS Mitigation](#4-perimeter-firewall--ddos-mitigation)
5. [Master Hardening Audit Checklist](#5-master-hardening-audit-checklist)

---

## 1. Operating System & Kernel Hardening

### 1.1 Minimal Footprint & Attack Surface Reduction
* **Principle**: Every installed software package represents a potential vulnerability. VPN gateways must be dedicated, single-purpose appliances.
* **Implementation**:
  * Install Ubuntu Server Minimal or Debian Minimal.
  * Remove all non-essential daemons (FTP, NFS, Samba, Apache, MySQL):
    ```bash
    apt-get purge -y rpcbind nfs-common samba apache2 nginx bind9
    apt-get autoremove -y
    ```

### 1.2 SSH Hardening (`/etc/ssh/sshd_config`)
* Never allow SSH administration from the public Internet WAN interface (`eth0`). Bind SSH strictly to internal LAN (`eth1`) or a dedicated out-of-band management VLAN.
* Disable password authentication; enforce SSH Ed25519 or RSA-4096 cryptographic keys.
* Enforce strict configuration rules:
  ```ssh-config
  Port 2222
  ListenAddress 192.168.10.1
  PermitRootLogin no
  PasswordAuthentication no
  ChallengeResponseAuthentication no
  PubkeyAuthentication yes
  KbdInteractiveAuthentication no
  X11Forwarding no
  AllowUsers vpnadmin
  MaxAuthTries 3
  ClientAliveInterval 300
  ClientAliveCountMax 2
  ```

### 1.3 Mandatory Access Control (AppArmor / SELinux)
* Ensure StrongSwan daemons (`charon`, `swanctl`) run confined under strict AppArmor or SELinux security profiles, preventing a buffer overflow vulnerability in `charon` from executing arbitrary system commands or accessing unauthorized filesystem paths:
  ```bash
  aa-status | grep -E "strongswan|charon"
  ```

---

## 2. Cryptographic Hardening & FIPS 140-2 Compliance

### 2.1 Eliminate Legacy Cryptographic Algorithms
Many organizations suffer breaches due to backward compatibility with obsolete VPN clients. TunnelPoint explicitly prohibits the following broken primitives:
* **IKEv1**: Vulnerable to Aggressive Mode PSK cracking and lacks modern Perfect Forward Secrecy enforcement.
* **3DES / DES**: 64-bit block size vulnerable to Sweet32 collision attacks.
* **MD5 / SHA-1**: Collision attacks allow forging X.509 certificates and HMAC tags.
* **Diffie-Hellman Groups 1, 2, and 5**: 768-bit and 1536-bit modular exponentiation algorithms can be cracked by nation-state actors using precompiled rainbow tables.

### 2.2 Enforce Modern AEAD & Elliptic Curves
* All production connections in `swanctl.conf` MUST use Authenticated Encryption with Associated Data (AEAD) ciphers and NIST/Brainpool elliptic curves:
  ```conf
  proposals = aes256gcm16-prfsha384-ecp384!
  esp_proposals = aes256gcm16-ecp384!
  ```

---

## 3. PKI & Key Management Lifecycle

### 3.1 Air-Gapped Root CA
* The Tier 1 Root Certificate Authority (`root-ca.key`) MUST NEVER reside on a networked computer.
* Generate the Root CA on an air-gapped machine or dedicated Hardware Security Module (HSM) / Trusted Platform Module (TPM). Once Intermediate CAs are signed, store the Root CA offline in a secure physical vault.

### 3.2 Automated 90-Day Certificate Rotation
* Leaf certificates for VPN gateways and remote workers must expire every 90 days (mirroring modern web browser standards).
* Implement automated monitoring using `/scripts/cert_monitor.sh` to trigger alerts 30 days prior to expiration.

---

## 4. Perimeter Firewall & DDoS Mitigation

### 4.1 SYN Cookie Enforcement
Under a TCP SYN flood DoS attack, the kernel's SYN backlog queue overflows, causing legitimate connections to drop. Ensure SYN cookies are active in `sysctl.conf`:
```sysctl
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 4096
```

### 4.2 Rate-Limiting IKE_SA_INIT (Anti-DDoS)
Attackers can flood UDP port 500 with bogus `IKE_SA_INIT` packets, forcing Gateway A to perform expensive Diffie-Hellman mathematical exponentiation until CPU hits 100%.
In Netfilter/nftables, enforce rate-limiting on new IKE requests from unverified sources:
```bash
iptables -A INPUT -i eth0 -p udp --dport 500 -m state --state NEW -m limit --limit 10/second --limit-burst 20 -j ACCEPT
```

---

## 5. Master Hardening Audit Checklist

Before transitioning a TunnelPoint gateway into production, verify every item:

| Audit Item | Hardening Requirement | Verification Command | Status |
| :--- | :--- | :--- | :---: |
| **OS 01** | IP Forwarding enabled | `sysctl net.ipv4.ip_forward` | `[x]` |
| **OS 02** | Strict RP-Filter (anti-spoofing) active | `sysctl net.ipv4.conf.all.rp_filter` | `[x]` |
| **OS 03** | ICMP Redirects completely disabled | `sysctl net.ipv4.conf.all.accept_redirects` | `[x]` |
| **OS 04** | SSH bound strictly to internal LAN/VLAN | `ss -tulpn \| grep 22` | `[x]` |
| **OS 05** | Root SSH login & passwords disabled | `grep -E "PermitRootLogin\|PasswordAuth" /etc/ssh/sshd_config` | `[x]` |
| **CRYPTO 01** | IKEv1 completely disabled | `grep -i "version = 2" /etc/swanctl/swanctl.conf` | `[x]` |
| **CRYPTO 02** | Only AES-GCM / SHA-384 / ECP-384 allowed | `swanctl --list-conns` | `[x]` |
| **CRYPTO 03** | Perfect Forward Secrecy (PFS) enforced | `grep -i "esp_proposals" /etc/swanctl/swanctl.conf` | `[x]` |
| **PKI 01** | Root CA private key absent from gateway | `ls /etc/swanctl/private/` (Verify no root key!) | `[x]` |
| **PKI 02** | Certificate trust chain verified | `openssl verify -CAfile /etc/swanctl/x509ca/ca-chain.crt ...` | `[x]` |
| **FW 01** | Default DROP policy on INPUT & FORWARD | `iptables -L -n -v` | `[x]` |
| **FW 02** | NAT Exemption rule placed at top of NAT | `iptables -t nat -L POSTROUTING -n -v` | `[x]` |
| **FW 03** | TCP MSS Clamping active in Mangle table | `iptables -t mangle -L FORWARD -n -v` | `[x]` |
