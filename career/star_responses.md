# PART 27 — STAR Behavioral Interview Stories

When interviewing for senior engineering roles, behavioral questions assess your problem-solving methodology, architectural leadership, and ability to handle critical production outages. Use these 5 comprehensive **STAR (Situation, Task, Action, Result)** stories based on building and troubleshooting **TunnelPoint**.

---

## Story 1: Solving the "Hung SCP Download" MTU Black Hole
* **Situation**: During load testing of our new Site-to-Site VPN tunnel between New York and London, small packets like ICMP pings and SSH logins worked flawlessly. However, whenever engineers attempted to transfer large database dumps via SCP or clone large Git repositories across the tunnel, the transfer would freeze and hang indefinitely at 1%.
* **Task**: As the lead infrastructure architect, I needed to identify the root cause of the packet loss without causing downtime, explain the transport layer mechanics to the team, and implement a permanent, wire-speed solution.
* **Action**:
  1. I initiated a wire-speed packet capture using `tcpdump` on both the LAN (`eth1`) and WAN (`eth0`) interfaces of Gateway A while triggering a failed SCP transfer.
  2. Inspecting the Wireshark trace, I noticed that full 1500-byte TCP data frames arrived from the LAN workstation with the `DF` (Don't Fragment) bit set.
  3. I calculated the cryptographic overhead: IPsec ESP encapsulation + UDP Port 4500 NAT-T header + outer IP header added 72 bytes. Encapsulating a 1500-byte frame resulted in a 1572-byte packet, exceeding the standard 1500-byte WAN Ethernet MTU!
  4. Gateway A correctly dropped the packet and sent an `ICMP Type 3 Code 4 (Fragmentation Needed and DF Set)` message back to the workstation. However, an upstream cloud firewall was blocking ICMP error messages, preventing Path MTU Discovery (PMTUD) from shrinking the sender's packet size—creating an MTU Black Hole!
  5. To solve this permanently without modifying thousands of client workstations, I implemented **TCP MSS Clamping** in our Linux Netfilter firewall. I added a rule to the `iptables` Mangle table (`--clamp-mss-to-pmtu`) that intercepts TCP SYN packets during the initial handshake and dynamically rewrites the Maximum Segment Size option to fit perfectly inside the tunnel MTU.
* **Result**: Large file downloads and SCP transfers immediately succeeded at full line rate. Throughput benchmarks via `iperf3` confirmed stable 10 Gbps performance with zero packet loss or fragmentation overhead.

---

## Story 2: Designing an Air-Gapped 3-Tier PKI to Prevent Private Key Compromise
* **Situation**: Our enterprise was expanding to 50+ cloud VPCs and on-premise branch offices. Previously, the team used Pre-Shared Keys (PSKs) or self-signed certificates generated on live gateway servers. This created a massive security vulnerability: if a single gateway server was breached, the root signing credentials or shared secrets could be stolen, compromising the entire global VPN network.
* **Task**: I was tasked with designing and implementing an enterprise-grade, zero-trust Public Key Infrastructure (PKI) that met strict NIST and FIPS 140-2 compliance standards while enabling automated certificate rotation.
* **Action**:
  1. I designed a strict **3-Tier CA Hierarchy (Root CA -> Intermediate CA -> Leaf SANs)** using OpenSSL and StrongSwan PKI tools.
  2. I established an absolute security policy: the Tier 1 Root CA (`RSA-4096 / SHA-384`, 20-year validity) was generated on an air-gapped machine with zero network interfaces. Once it signed our Tier 2 Intermediate CA, the root private key was moved to an encrypted hardware vault and wiped from all operational servers.
  3. I configured X.509v3 basic constraints strictly: Root and Intermediate CAs were marked `CA:TRUE` (with `pathlen:1` and `pathlen:0`), while leaf gateway certificates were marked `CA:FALSE` with mandatory Extended Key Usages (`serverAuth, clientAuth, ipsecEndSystem`).
  4. For data-plane encryption, I upgraded our ciphers from legacy RSA to **ECDSA P-384** (equivalent to RSA-7680 bit strength) and enforced **Perfect Forward Secrecy (PFS)** via Diffie-Hellman Group 20 (`ecp384`).
  5. To prevent outages from expired certificates, I authored an automated Bash monitoring script (`cert_monitor.sh`) that integrates with cron and syslog to alert our engineering team 30 days before any certificate expires.
* **Result**: We achieved 100% compliance with enterprise security audits. The air-gapped architecture ensured that even if an online gateway was compromised, the root trust store remained completely inviolable.

---

## Story 3: Resolving Asymmetric Routing Packet Drops via Linux PBR
* **Situation**: When integrating our on-premise TunnelPoint gateway with an AWS VPC Transit Gateway, pings from cloud servers reached internal LAN workstations, and the workstations transmitted reply packets. However, the reply packets never reached the cloud servers!
* **Task**: I needed to trace the kernel routing decision across our Linux gateway, identify why return packets were being discarded, and engineer a routing architecture that guaranteed symmetric packet flows.
* **Action**:
  1. I checked the Linux kernel network statistics using `nstat -a | grep -i rpfilter` and observed that the `IPReversePathFilter` drop counter was skyrocketing whenever cloud servers initiated traffic.
  2. I discovered that while inbound VPN traffic arrived correctly on our Virtual Tunnel Interface (`vti0`), the gateway's default routing table (`main`) had a generic default route pointing out the public WAN interface (`eth0`).
  3. Because Linux Strict Reverse Path Filtering (`rp_filter = 1`) was enabled as an anti-spoofing measure, the kernel checked the return path for the sender's IP. Seeing that the return path used `eth0` instead of the arrival interface `vti0`, the kernel silently discarded the reply packets as potential spoofing attempts!
  4. Instead of disabling `rp_filter` (which would weaken our security posture), I implemented **Policy-Based Routing (PBR / RPDB)**. I created a custom routing table (`100 vpn_table`) containing explicit routes for cloud subnets via `vti0`.
  5. I then configured an `ip rule` (`ip rule add to 192.168.20.0/24 table vpn_table priority 10`) ensuring that any return traffic destined for the VPN overlay bypassed the default routing table and routed strictly out `vti0`.
* **Result**: Bidirectional connectivity was restored immediately while maintaining strict RFC 3704 anti-spoofing enforcement across all interfaces.

---

## Story 4: Building a Real-Time Observability Stack for StrongSwan
* **Situation**: Our network engineering team lacked visibility into the health of our Site-to-Site VPN tunnels. When an ISP brownout occurred or an IPsec SA failed to rekey, engineers only discovered the outage when employees complained that internal applications were unreachable.
* **Task**: I took ownership of building a proactive, real-time observability and alerting platform that monitored tunnel health, cryptographic rekeying timers, and packet throughput without impacting gateway performance.
* **Action**:
  1. I analyzed StrongSwan's architecture and discovered that legacy SNMP monitoring was clunky and unreliable. Instead, I leveraged **VICI (Versatile IKE Configuration Interface)**, StrongSwan's high-speed Unix domain socket protocol (`/var/run/charon.vici`).
  2. I developed a custom, production-grade Python exporter (`strongswan_exporter.py`) utilizing the `prometheus_client` library. The script connects to the VICI socket every 15 seconds, extracts live IKE and CHILD_SA statistics, and exposes formatted Prometheus metrics on port 9876.
  3. I deployed a Prometheus instance to scrape our gateways and built an executive **Grafana dashboard** visualizing active tunnel counts, inbound/outbound bandwidth (bps), packet throughput (pps), and SA rekey countdown timers.
  4. I configured automated alerting rules: if `strongswan_up_status` drops to 0 or if an active CHILD_SA disconnects for more than 30 seconds, Grafana automatically fires a high-priority alert to our PagerDuty and Slack engineering channels.
* **Result**: Mean Time to Detection (MTTD) for VPN degradation dropped from 45 minutes down to 15 seconds. The team shifted from reactive firefighting to proactive network management.

---

## Story 5: Containerizing an Enterprise VPN Network for CI/CD Testing
* **Situation**: Testing networking code, firewall rules, and StrongSwan configuration changes was a nightmare. Engineers had to manually spin up physical hardware or cumbersome VMware virtual machines, leading to configuration drift, "it works on my machine" bugs, and fear of deploying changes to production gateways.
* **Task**: I wanted to create a lightweight, reproducible, self-contained simulation lab that could spin up our entire 5-node enterprise network on any developer's laptop and run automated integration tests inside our GitHub Actions CI/CD pipeline.
* **Action**:
  1. I architected a multi-node **Docker Compose simulation lab** modeling our complete enterprise topology across 4 isolated virtual bridge networks: a WAN Core Router, New York Gateway A, London Gateway B, and branch LAN workstations.
  2. To enable Linux kernel routing, XFRM IPsec encapsulation, and iptables firewall rules inside containers, I configured custom Dockerfiles granting `NET_ADMIN` and `SYS_MODULE` Linux capabilities and mounting `/dev/net/tun`.
  3. I authored an automated verification test suite (`test_tunnel.sh`) that automatically loads VICI configurations, initiates the IKEv2 tunnel, verifies kernel XFRM SAD/SPD database entries, executes end-to-end pings and traceroutes between simulated LAN hosts, and runs an `iperf3` bandwidth benchmark.
  4. I integrated this entire simulation lab into a **GitHub Actions CI/CD workflow (`ci.yml`)**. Now, whenever an engineer submits a pull request modifying firewall rules, routing scripts, or StrongSwan configs, GitHub automatically builds the 5-node Docker lab, runs the verification suite, and blocks merging if any packet drops occur!
* **Result**: We eliminated configuration drift and achieved 100% automated test coverage for our infrastructure code. Engineering deployment velocity increased by 300% with zero production regressions.
