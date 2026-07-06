# PART 27 — Resume Bullet Points & Project Descriptions

Use these tailored, high-impact bullet points on your resume or LinkedIn profile to showcase your engineering mastery of **TunnelPoint**. They are categorized by target engineering role and structured using the action-result-metric format.

---

## 1. Network Engineer / Infrastructure Architect
* **Project Title**: *TunnelPoint — Enterprise Secure Site-to-Site VPN Platform & Overlay Network*
* **Bullet Points**:
  * Architected and deployed an enterprise-grade, multi-node Site-to-Site VPN platform using **StrongSwan IKEv2** and Linux **Route-Based Virtual Tunnel Interfaces (VTI / XFRM)** across simulated global WAN ASNs.
  * Engineered Linux kernel network stacks, tuning `/etc/sysctl.conf` parameters for multi-gigabit routing, SYN flood cookie defense, and strict **RFC 3704 Reverse Path Filtering (`rp_filter`)** anti-spoofing protection.
  * Designed and implemented advanced **Policy-Based Routing (PBR / RPDB)** and multi-table FIB routing hierarchies, isolating encrypted overlay traffic from public Internet gateways.
  * Resolved complex MTU fragmentation black holes by implementing dynamic **TCP MSS Clamping (`--clamp-mss-to-pmtu`)** across Netfilter Mangle tables, achieving multi-gigabit high-throughput routing verified via automated `iperf3` lab suites.

---

## 2. Cybersecurity Engineer / PKI Architect
* **Project Title**: *TunnelPoint — Zero-Trust Cryptographic VPN & 3-Tier CA Hierarchy*
* **Bullet Points**:
  * Designed and built an automated, enterprise **3-Tier X.509 Public Key Infrastructure (Root CA -> Intermediate CA -> Leaf SANs)** using OpenSSL and StrongSwan PKI, enforcing strict basic constraints and key usages.
  * Hardened data-plane encryption to exceed NIST and FIPS 140-2 standards, enforcing **AES-256-GCM-16** Authenticated Encryption, **SHA-384** hashing, and **ECDH Curve P-384 (NIST Group 20)**.
  * Implemented 100% **Perfect Forward Secrecy (PFS)** by decoupling Phase 1 (`IKE_SA`) and Phase 2 (`CHILD_SA`) Diffie-Hellman key exchanges, guaranteeing zero historical data compromise against private key theft.
  * Developed a zero-trust perimeter defense ruleset in **`iptables` and `nftables`**, enforcing default-drop policies, IKEv2/UDP 4500 NAT Traversal encapsulation, and stateful `nf_conntrack` inspection.

---

## 3. DevOps Engineer / Cloud Infrastructure Architect
* **Project Title**: *TunnelPoint — Multi-Cloud IaC VPN Automation & Simulation Lab*
* **Bullet Points**:
  * Authored production **Infrastructure-as-Code (Terraform)** blueprints deploying automated Site-to-Site VPN gateways across **AWS VPC Transit Gateway** and **Azure Virtual Network Gateway** with custom IPsec policies.
  * Containerized a complete 5-node enterprise network simulation lab using **Docker Compose** and custom Ubuntu 24.04 builds, utilizing `NET_ADMIN` and `SYS_MODULE` capabilities for kernel routing testing.
  * Developed enterprise automation Bash scripts (`deploy.sh`, `health_check.sh`, `backup.sh`) with OpenSSL AES-256-GCM encrypted backup archiving and automated 30-day PKI certificate expiration alerting.
  * Built an automated **GitHub Actions CI/CD pipeline** executing static Bash linting (`shellcheck`), Terraform syntax validation, and automated container lab spin-up with end-to-end integration testing.

---

## 4. Site Reliability Engineer (SRE) / Systems Engineer
* **Project Title**: *TunnelPoint — High-Availability VPN Observability & Troubleshooting Engine*
* **Bullet Points**:
  * Engineered a custom **Python StrongSwan VICI metrics exporter** interfacing directly with Unix domain sockets (`/var/run/charon.vici`) to scrape live IKE/IPsec SAs, rekey timers, and packet throughput.
  * Deployed a complete observability stack integrating **Prometheus** and **Grafana**, building real-time dashboards tracking tunnel uptime, packet drop rates, and node CPU/memory utilization.
  * Authored an exhaustive 30-problem troubleshooting playbook resolving production IKE proposal mismatches, asymmetric routing packet drops, NAT-T port blocking, and certificate revocation timeouts.

---

## 5. Software Engineer (SWE) / Backend Systems Engineer
* **Project Title**: *TunnelPoint — Enterprise Secure Site-to-Site VPN Platform & Backend Networking Engine*
* **Bullet Points**:
  * Built an enterprise Site-to-Site VPN platform and Linux networking engine using **StrongSwan IKEv2** and **Route-Based Virtual Tunnel Interfaces (XFRM)**, optimizing kernel data-plane routing for high-throughput multi-gigabit data streams.
  * Developed a custom **Python observability service** interfacing directly with Unix domain sockets (`/var/run/charon.vici`) to scrape real-time cryptographic SAs, rekey timers, and packet metrics into **Prometheus and Grafana**.
  * Engineered an automated **3-Tier OpenSSL PKI hierarchy** enforcing **AES-256-GCM** and **ECDH Curve P-384 Perfect Forward Secrecy**, and built a 5-node **Docker Compose** lab with an automated **GitHub Actions CI/CD** testing suite.
  * Leveraged Linux zero-copy `sk_buff` pointer manipulation and Netlink sockets to achieve wire-speed packet encapsulation and routing across virtual network namespaces (`netns`).

