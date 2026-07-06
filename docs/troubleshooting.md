# PART 19 — The Ultimate Senior Engineer VPN Troubleshooting Playbook

This document is an exhaustive, production-grade troubleshooting manual for **TunnelPoint (Enterprise Secure Site-to-Site VPN Platform)**. It categorizes over 30 real-world production network, cryptographic, and system failures encountered in enterprise IPsec/IKEv2 deployments, providing the exact diagnostic commands, log signatures, root causes, and remediation steps.

---

## Table of Contents
1. [Phase 1 (IKE_SA) Key Exchange Failures](#1-phase-1-ikesa-key-exchange-failures)
2. [Phase 2 (CHILD_SA) Data Plane Failures](#2-phase-2-childsa-data-plane-failures)
3. [Routing, Firewall & NAT Traversal Failures](#3-routing-firewall--nat-traversal-failures)
4. [MTU, MSS Clamping & Fragmentation Black Holes](#4-mtu-mss-clamping--fragmentation-black-holes)
5. [PKI, Certificate & Revocation Failures](#5-pki-certificate--revocation-failures)
6. [Master Diagnostic Command Reference](#6-master-diagnostic-command-reference)

---

## 1. Phase 1 (IKE_SA) Key Exchange Failures

### 1.1 NO_PROPOSAL_CHOSEN during IKE_SA_INIT
* **Log Signature (`/var/log/strongswan.log`)**:
  ```
  charon[1234]: 01[IKE] <tunnelpoint-s2s|1> IKE_SA tunnelpoint-s2s[1] state change: CREATED => CONNECTING
  charon[1234]: 01[ENC] <tunnelpoint-s2s|1> generating IKE_SA_INIT request 0 [ SA KE No N(NATD_S_IP) N(NATD_D_IP) N(HASH_ALG) ]
  charon[1234]: 01[NET] <tunnelpoint-s2s|1> sending packet: from 203.0.113.10[500] to 198.51.100.20[500]
  charon[1234]: 02[NET] <tunnelpoint-s2s|1> received packet: from 198.51.100.20[500] to 203.0.113.10[500]
  charon[1234]: 02[ENC] <tunnelpoint-s2s|1> parsed IKE_SA_INIT response 0 [ N(NO_PROP) ]
  charon[1234]: 02[IKE] <tunnelpoint-s2s|1> received NO_PROPOSAL_CHOSEN notify error
  ```
* **Root Cause**: The cryptographic algorithms (Encryption, Integrity/Hash, or Diffie-Hellman Group) proposed by Gateway A do not match any allowed proposals configured on Gateway B.
* **Diagnosis**:
  ```bash
  # Check active proposals on Gateway A
  swanctl --list-conns | grep proposals
  # Compare with Gateway B configuration
  docker exec -t tunnelpoint-gateway-b swanctl --list-conns | grep proposals
  ```
* **Remediation**: Ensure both gateways have identical algorithm strings in `swanctl.conf`:
  ```conf
  proposals = aes256gcm16-prfsha384-ecp384!
  ```
  *(Note: The trailing `!` disables automatic fallback to default legacy ciphers).*

### 1.2 INVALID_KE_PAYLOAD (Diffie-Hellman Group Mismatch)
* **Log Signature**:
  ```
  charon[1234]: 03[IKE] remote host rejected Diffie-Hellman group 20 (ECP_384), requesting group 14 (MODP_2048)
  charon[1234]: 03[IKE] received INVALID_KE_PAYLOAD notify, retrying with requested DH group 14
  ```
* **Root Cause**: Gateway A initiated the Diffie-Hellman key exchange using Elliptic Curve Group 20 (`ecp384`), but Gateway B is configured to require modular exponentiation Group 14 (`modp2048`).
* **Remediation**: Align the DH group across both nodes. In enterprise environments, never downgrade to `modp2048` (2048-bit RSA equivalent); instead, upgrade Gateway B to support `ecp384` (Curve P-384) or `curve25519`.

### 1.3 AUTHENTICATION_FAILED (Certificate SAN Mismatch or PSK Error)
* **Log Signature**:
  ```
  charon[1234]: 04[IKE] <tunnelpoint-s2s|2> peer requested EAP, responding with EAP_NAK
  charon[1234]: 04[ENC] parsed IKE_AUTH response 1 [ N(AUTH_FAIL) ]
  charon[1234]: 04[IKE] received AUTHENTICATION_FAILED notify error
  ```
* **Root Cause**: When using X.509 certificates, the Subject Alternative Name (SAN) presented in the peer's certificate does not match the string configured in `remote { id = ... }`. When using Pre-Shared Keys (PSK), the secret string in `secrets { ike { ... } }` differs.
* **Remediation**:
  1. Inspect the exact SAN embedded in the peer certificate:
     ```bash
     openssl x509 -in /etc/swanctl/x509/gateway-b.crt -noout -ext subjectAltName
     # Output: X509v3 Subject Alternative Name: DNS:gateway-b.tunnelpoint.io, IP Address:198.51.100.20
     ```
  2. Ensure Gateway A's `remote.id` explicitly matches:
     ```conf
     remote {
         id = gateway-b.tunnelpoint.io
     ```

### 1.4 Clock Skew & Time Synchronization Failure
* **Log Signature**:
  ```
  charon[1234]: 05[CFG] <tunnelpoint-s2s|3> certificate status is not valid yet: notBefore is 2026-07-06 18:00:00 UTC, current time is 2026-07-06 17:05:00 UTC
  charon[1234]: 05[IKE] <tunnelpoint-s2s|3> no trusted RSA public key found for 'gateway-b.tunnelpoint.io'
  ```
* **Root Cause**: The system clock on one of the gateways is out of sync by more than a few minutes, causing X.509 certificate validity timestamps (`notBefore` / `notAfter`) to fail validation.
* **Remediation**: Install and synchronize an NTP daemon (`chrony` or `systemd-timesyncd`):
  ```bash
  chronyc sources -v
  timedatectl status | grep "NTP service"
  ```

---

## 2. Phase 2 (CHILD_SA) Data Plane Failures

### 2.1 TS_UNACCEPTABLE (Traffic Selector Mismatch)
* **Log Signature**:
  ```
  charon[1234]: 06[IKE] <tunnelpoint-s2s|4> IKE_SA tunnelpoint-s2s[4] established between 203.0.113.10[gateway-a.tunnelpoint.io]...198.51.100.20[gateway-b.tunnelpoint.io]
  charon[1234]: 06[ENC] <tunnelpoint-s2s|4> parsed CREATE_CHILD_SA response 2 [ N(TS_UNACCEPT) ]
  charon[1234]: 06[IKE] <tunnelpoint-s2s|4> received TS_UNACCEPTABLE notify, no CHILD_SA built
  ```
* **Root Cause**: Phase 1 (`IKE_SA`) succeeded, but Phase 2 (`CHILD_SA`) failed because the subnet definitions (`local_ts` and `remote_ts`) do not mirror exactly between peers. For example, Gateway A proposes `192.168.10.0/24 === 192.168.20.0/24`, but Gateway B is configured for `192.168.20.0/24 === 192.168.0.0/16`.
* **Remediation**: Verify traffic selectors match inversely across peers:
  * **Gateway A**: `local_ts = 192.168.10.0/24`, `remote_ts = 192.168.20.0/24`
  * **Gateway B**: `local_ts = 192.168.20.0/24`, `remote_ts = 192.168.10.0/24`

### 2.2 Perfect Forward Secrecy (PFS) Group Mismatch
* **Log Signature**:
  ```
  charon[1234]: 07[IKE] <tunnelpoint-s2s|4> failed to establish CHILD_SA, proposals: AES_GCM_16_256/MODP_2048/NO_EXT_SEQ vs AES_GCM_16_256/ECP_384/NO_EXT_SEQ
  ```
* **Root Cause**: One gateway demands a fresh Diffie-Hellman key exchange during Phase 2 (`esp_proposals = aes256gcm16-ecp384!`), while the peer has PFS disabled or configured with a different DH curve.
* **Remediation**: Ensure both nodes include the exact same DH group in their `esp_proposals`:
  ```conf
  esp_proposals = aes256gcm16-ecp384!
  ```

### 2.3 ESP Protocol (IP Proto 50) Blocked by Upstream ISP/Firewall
* **Symptom**: `IKE_SA` negotiates successfully on UDP port 500. `swanctl --list-sas` shows `INSTALLED`, but zero bytes are received (`bytes_i = 0`), and pings across the tunnel fail 100%.
* **Diagnosis**:
  ```bash
  # Check kernel XFRM state counters
  ip -s xfrm state
  # Observe that tx bytes increment, but rx bytes remain at 0!
  ```
* **Root Cause**: An upstream cloud provider, NAT router, or ISP ISP firewall is blocking raw IP Protocol 50 (Encapsulating Security Payload - ESP).
* **Remediation**: Enforce UDP Encapsulation (NAT Traversal / NAT-T) in `swanctl.conf`:
  ```conf
  encap = yes
  ```
  This forces StrongSwan to wrap ESP packets inside **UDP Port 4500** headers, bypassing raw IP Protocol 50 firewalls!

---

## 3. Routing, Firewall & NAT Traversal Failures

### 3.1 Asymmetric Routing & Reverse Path Filtering (`rp_filter`) Drops
* **Symptom**: Host A pings Host B. Packet capture on Gateway B shows ICMP Echo Requests arriving via `vti0` and forwarding to Host B. Host B replies, but Gateway B silently drops the ICMP Echo Reply!
* **Diagnosis**: Check Linux kernel dropped packet counters due to Reverse Path Filtering:
  ```bash
  nstat -a | grep -i rpfilter
  # Output: IpExtInNoECTPkts / IpExtInOctets / IPReversePathFilter (incrementing rapidly!)
  ```
* **Root Cause**: Linux Strict Reverse Path Filtering (`rp_filter = 1`) verifies that the return route to a packet's source IP uses the same interface the packet arrived on. If routing tables are misconfigured, the kernel drops the packet as an anti-spoofing measure.
* **Remediation**: In `setup_routing.sh`, ensure strict PBR rules direct LAN return traffic back into the tunnel interface:
  ```bash
  ip rule add to 192.168.10.0/24 table vpn_table priority 10
  ip route add 192.168.10.0/24 dev vti0 table vpn_table
  ```

### 3.2 Missing NAT Exemption Rule (VPN Traffic Masqueraded)
* **Symptom**: Pings from Host A (`192.168.10.50`) reach Gateway B, but arrive with source IP `203.0.113.10` (Gateway A's public WAN IP) instead of `192.168.10.50`! The packet is dropped by Gateway B's XFRM policy.
* **Root Cause**: The general Internet masquerade rule (`iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE`) executed *before* checking if the traffic was destined for the VPN tunnel!
* **Remediation**: Always place an explicit NAT Exemption (ACCEPT) rule at the very top of the `POSTROUTING` chain:
  ```bash
  iptables -t nat -I POSTROUTING 1 -s 192.168.10.0/24 -d 192.168.20.0/24 -j ACCEPT
  ```

### 3.3 FORWARD Chain Default DROP Blocking Transit Traffic
* **Symptom**: `swanctl --list-sas` is `INSTALLED`, routes exist, but ping fails. `iptables -L FORWARD -v -n` shows packet drop counters incrementing on the default policy.
* **Remediation**: Explicitly authorize bidirectional forwarding between LAN (`eth1`) and tunnel (`vti0`):
  ```bash
  iptables -A FORWARD -i eth1 -o vti0 -s 192.168.10.0/24 -d 192.168.20.0/24 -j ACCEPT
  iptables -A FORWARD -i vti0 -o eth1 -s 192.168.20.0/24 -d 192.168.10.0/24 -j ACCEPT
  ```

---

## 4. MTU, MSS Clamping & Fragmentation Black Holes

### 4.1 The "Hang on Large Download / SCP" Phenomenon (PMTUD Failure)
* **Symptom**: Small packets (ICMP ping, SSH login, DNS queries) work perfectly across the VPN tunnel. However, large data transfers (SCP, HTTP file downloads, `iperf3`, `git clone`) freeze and hang indefinitely after transferring a few kilobytes!
* **Root Cause**:
  1. Standard Ethernet link MTU is **1500 bytes**.
  2. IPsec ESP encapsulation + UDP 4500 header + outer IP header adds **56 to 80 bytes** of cryptographic overhead.
  3. When Host A transmits a full 1500-byte TCP frame with the `DF` (Don't Fragment) bit set, Gateway A cannot encapsulate it without exceeding the 1500-byte WAN MTU!
  4. Gateway A drops the packet and sends an `ICMP Type 3 Code 4 (Fragmentation Needed and DF Set)` message back to Host A.
  5. If an intermediate firewall blocks ICMP error messages, Host A never learns to shrink its packet size, creating an **MTU Fragmentation Black Hole**!
* **Diagnosis**:
  ```bash
  # Test with large ping payloads with DF bit set
  ping -M do -s 1472 192.168.20.50 # Fails!
  ping -M do -s 1350 192.168.20.50 # Succeeds!
  ```
* **Remediation**: Implement **TCP MSS Clamping** in Netfilter Mangle table. This intercepts TCP SYN packets during the initial handshake and dynamically rewrites the Maximum Segment Size option to fit within the tunnel MTU:
  ```bash
  iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -s 192.168.10.0/24 -d 192.168.20.0/24 -j TCPMSS --clamp-mss-to-pmtu
  iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -s 192.168.20.0/24 -d 192.168.10.0/24 -j TCPMSS --clamp-mss-to-pmtu
  ```
  Additionally, explicitly set VTI interface MTU to 1400:
  ```bash
  ip link set dev vti0 mtu 1400
  ```

---

## 5. PKI, Certificate & Revocation Failures

### 5.1 UNTRUSTED_KEY (Missing CA Chain)
* **Log Signature**:
  ```
  charon[1234]: 08[IKE] <tunnelpoint-s2s|5> received end entity cert "CN=gateway-b.tunnelpoint.io"
  charon[1234]: 08[CFG] <tunnelpoint-s2s|5> using certificate "CN=gateway-b.tunnelpoint.io"
  charon[1234]: 08[CFG] <tunnelpoint-s2s|5> no issuer certificate found for "CN=TunnelPoint Intermediate CA"
  charon[1234]: 08[IKE] <tunnelpoint-s2s|5> no trusted RSA public key found for 'gateway-b.tunnelpoint.io'
  ```
* **Root Cause**: Gateway A received Gateway B's leaf certificate during negotiation, but Gateway A does not have the `TunnelPoint Intermediate CA` or `Root CA` installed in `/etc/swanctl/x509ca/`.
* **Remediation**: Copy the unified CA certificate chain bundle to all gateway nodes:
  ```bash
  cp /pki/build/cacerts/ca-chain.crt /etc/swanctl/x509ca/
  swanctl --load-creds
  ```

### 5.2 CERTIFICATE_REVOKED or CRL Check Timeout
* **Log Signature**:
  ```
  charon[1234]: 09[CFG] <tunnelpoint-s2s|6> checking revocation status of "CN=gateway-b.tunnelpoint.io"
  charon[1234]: 09[CFG] <tunnelpoint-s2s|6> fetching CRL from 'http://crl.tunnelpoint.io/intermediate.crl' failed: Connection timed out
  charon[1234]: 09[CFG] <tunnelpoint-s2s|6> revocation check for certificate failed, rejecting connection
  ```
* **Root Cause**: StrongSwan is enforcing strict Certificate Revocation List (CRL) checking, but the CRL HTTP distribution point is unreachable from the isolated gateway network.
* **Remediation**: In high-security environments, mirror the CRL file locally to `/etc/swanctl/x509crl/`. In closed-loop labs, disable strict CRL checking in `strongswan.conf`:
  ```conf
  charon {
      plugins {
          revocation {
              enable = no
          }
      }
  }
  ```

---

## 6. Master Diagnostic Command Reference

When troubleshooting a down VPN tunnel, execute this systematic 6-step diagnostic checklist on the Linux gateway:

```bash
# 1. Check StrongSwan Daemon Status & Active Connections
swanctl --list-conns
swanctl --list-sas

# 2. Inspect Live Key Exchange & Error Logs (Real-Time Tail)
tail -f /var/log/strongswan.log | grep -E "IKE|ENC|CFG|error|failed|rejected|mismatch"

# 3. Verify Linux Kernel XFRM Security Associations (SAD) & Policies (SPD)
ip -s xfrm state
ip -s xfrm policy

# 4. Check Virtual Tunnel Interface (VTI) Status & Counters
ip -s link show dev vti0
ip route show table vpn_table

# 5. Inspect Netfilter Firewall Drop Counters & Conntrack State
iptables -L -n -v | grep -i drop
conntrack -L | grep -E "500|4500|192.168"

# 6. Perform Raw Wire-Speed Packet Capture on Public WAN & Tunnel Interfaces
# Capture IKE handshakes and ESP/UDP 4500 encrypted data on WAN:
tcpdump -nn -i eth0 "udp port 500 or udp port 4500 or proto 50" -v
# Capture decrypted cleartext traffic inside virtual tunnel interface:
tcpdump -nn -i vti0 -v
```
