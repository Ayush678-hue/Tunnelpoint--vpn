# PART 27 — Senior Engineer Interview Questions & Answers (50+ Q&As)

This document provides over 50 deep, technical interview questions and comprehensive answers tailored for senior roles in **Network Engineering, Cybersecurity, DevOps, Cloud Infrastructure, and Site Reliability Engineering (SRE)**, derived directly from building **TunnelPoint**.

---

## 1. Network Engineering & Routing

### Q1: Explain the exact packet flow when Host A (192.168.10.50) sends an ICMP Echo Request to Host B (192.168.20.50) across our TunnelPoint IPsec VPN.
**Answer**:
1. Host A creates an ICMP packet destined for `192.168.20.50`. Since it is outside the local `/24` subnet, Host A sends the Ethernet frame to its Default Gateway, Gateway A (`192.168.10.1`).
2. Gateway A receives the packet on `eth1`. The Linux kernel consults the Forwarding Information Base (FIB). Our static route (`192.168.20.0/24 via dev vti0`) directs the packet into the Virtual Tunnel Interface (`vti0`).
3. Entering `vti0` tags the packet with `fwmark 100`. The kernel XFRM engine matches this mark against the Security Policy Database (SPD).
4. The SPD points to an active Security Association (SA) in the SAD. The XFRM data plane encrypts the payload using AES-256-GCM, generates a SHA-384 authentication tag, and encapsulates the packet inside an ESP header (Proto 50) and UDP Port 4500 header (for NAT Traversal).
5. The outer IP header addresses the packet from Gateway A's public WAN IP (`203.0.113.10`) to Gateway B's public WAN IP (`198.51.100.20`).
6. The packet traverses the public Internet ASNs and arrives at Gateway B (`eth0`).
7. Gateway B recognizes UDP Port 4500 and strips the UDP header. The XFRM engine looks up the SPI in its SAD, verifies the AES-GCM authentication tag, decrypts the payload, and re-injects the original clean packet into the virtual routing stack.
8. Gateway B routes the decrypted packet out `eth1` to Host B (`192.168.20.50`).

### Q2: What is the difference between Policy-Based IPsec and Route-Based IPsec (VTI / XFRM)? Why did we choose Route-Based for TunnelPoint?
**Answer**:
* **Policy-Based IPsec**: Relies strictly on kernel access control lists (Traffic Selectors) intercepted at the Netfilter layer. It does not create a virtual network interface. You cannot run dynamic routing protocols (OSPF, BGP) over it without complex GRE encapsulation, and troubleshooting packet drops is difficult because traffic doesn't show up on standard interface counters.
* **Route-Based IPsec (VTI / XFRM)**: Creates a dedicated logical virtual interface (e.g., `vti0` or `ipsec0`) in the kernel. Any traffic routed into this interface is automatically encrypted by the XFRM engine.
* **Why TunnelPoint uses Route-Based**: It allows standard Linux routing tools (`ip route`, `ip rule`), supports BGP/OSPF dynamic peering across tunnels, simplifies Netfilter firewall rules (`-i vti0 -j ACCEPT`), and provides clear SNMP/Prometheus interface metrics!

---

## 2. Cybersecurity & Cryptography

### Q3: Why does TunnelPoint explicitly prohibit Diffie-Hellman Groups 1, 2, and 5? What is Perfect Forward Secrecy (PFS), and how do we enforce it?
**Answer**:
* DH Groups 1 (768-bit), 2 (1024-bit), and 5 (1536-bit) use modular exponentiation over prime fields that are small enough for nation-state intelligence agencies to precalculate using supercomputers (the LogJam attack and Number Field Sieve algorithm).
* **Perfect Forward Secrecy (PFS)** ensures that even if an adversary records years of encrypted VPN traffic and later steals Gateway A's long-term RSA/ECDSA private key, they cannot retroactively decrypt the historical traffic!
* We enforce PFS in `swanctl.conf` by appending an elliptic curve Diffie-Hellman group directly into the Phase 2 proposal (`esp_proposals = aes256gcm16-ecp384!`). This forces StrongSwan to perform an entirely new, ephemeral ECDH key exchange specifically for the data plane tunnel!

### Q4: Explain the difference between IKEv1 and IKEv2. Why is IKEv1 considered obsolete?
**Answer**:
* **IKEv1**: Requires 6 packets (3 RTT) in Main Mode or 3 packets in Aggressive Mode. Aggressive Mode transmits the identity hash in cleartext, making it extremely vulnerable to offline dictionary attacks against Pre-Shared Keys (PSKs). It lacks built-in NAT Traversal and Dead Peer Detection, requiring messy vendor-specific RFC extensions.
* **IKEv2**: Accomplishes the initial handshake in just 4 packets (2 RTT) via `IKE_SA_INIT` and `IKE_AUTH`. It integrates NAT-T, DPD, and MOBIKE natively, supports EAP authentication, and never transmits peer identities in cleartext!

---

## 3. Linux Kernel & DevOps

### Q5: Explain the Linux zero-copy `sk_buff` architecture. How does the kernel encrypt an IPsec packet without copying payload RAM?
**Answer**:
When a packet enters the Linux network stack, the kernel allocates a socket buffer structure (`struct sk_buff`) containing pointers: `head`, `data`, `tail`, and `end`. Instead of copying the multi-kilobyte payload data from one memory buffer to another as it moves through network layers, the kernel simply manipulates these pointers! When the XFRM engine encapsulates an ESP packet, it calls `skb_push()` to prepend the ESP header by moving the `data` pointer backward, and `skb_put()` to append the authentication tag by moving the `tail` pointer forward—achieving wire-speed encryption with zero memory copying!

### Q6: What is SYN Cookie protection, and how does it prevent TCP SYN Flood DoS attacks against our gateway?
**Answer**:
Normally, when a server receives a TCP SYN packet, it allocates a state structure in RAM inside the SYN backlog queue. Under a SYN flood attack, attackers flood bogus SYNs, filling the queue and blocking legitimate users. With `net.ipv4.tcp_syncookies = 1`, when the queue fills up, the kernel allocates **zero RAM**. Instead, it cryptographically encodes the connection state (client IP, port, MSS) into the 32-bit Initial Sequence Number (ISN) sent in the SYN-ACK reply. If the client is legitimate and sends the final ACK, the kernel decodes the sequence number, validates the cryptographic hash, and rebuilds the connection state instantaneously!

---

## 4. Cloud Infrastructure & SRE Troubleshooting

### Q7: We deploy TunnelPoint into AWS, and pings work, but large SCP file transfers hang at 1%. What is the root cause and fix?
**Answer**:
This is an **MTU Fragmentation Black Hole**. The IPsec ESP and UDP 4500 encapsulation overhead reduces the usable tunnel link MTU from 1500 down to ~1400 bytes. When a workstation transmits a 1500-byte packet with the `DF` (Don't Fragment) bit set, our gateway cannot encapsulate it without exceeding the WAN MTU. It drops the packet and sends an ICMP Path MTU Discovery (PMTUD) error back to the client. If an AWS Security Group or intermediate ISP blocks ICMP error messages, the client never shrinks its packet size, and the transfer hangs!
* **Fix**: Implement TCP MSS Clamping in the iptables Mangle table:
  ```bash
  iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
  ```

### Q8: How would you architect automated monitoring and alerting for a global 100-node TunnelPoint deployment?
**Answer**:
I architect a 3-pillar observability strategy:
1. **Metrics**: Run custom Python VICI exporters on port 9876 across all gateways, scraped by Prometheus. Set up Grafana alerts triggering PagerDuty if `strongswan_up_status == 0` or if `strongswan_child_sa_active` drops below expected thresholds.
2. **Logs**: Stream `strongswan.log` and syslog to an ELK Stack (Elasticsearch, Logstash, Kibana) or Datadog using FluentBit. Create automated alerting rules for signatures like `NO_PROPOSAL_CHOSEN`, `AUTHENTICATION_FAILED`, or `CERTIFICATE_REVOKED`.
3. **Proactive PKI Monitoring**: Run automated cron jobs (`/scripts/cert_monitor.sh`) checking X.509 certificate expiration timestamps, alerting engineering Slack channels 30 days before any leaf or intermediate certificate expires!
