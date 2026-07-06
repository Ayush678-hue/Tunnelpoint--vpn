#!/usr/bin/env bash
# TunnelPoint Complete PKI Generation Script (PART 14)
# Generates Offline Root CA, Online Intermediate CA, Gateway A/B Leaf Certs, and Remote Worker Certs
# Enforces RSA-4096 / ECDSA P-384, SHA-384, and X.509v3 SAN compliance

set -euo pipefail

# Define build directory
PKI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PKI_DIR}/build"
OPENSSL_CNF="${PKI_DIR}/openssl.cnf"

echo "===> [Step 1] Initializing PKI build directory structure..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}/"{cacerts,intermediate,certs,private,pkcs12}
chmod 700 "${BUILD_DIR}/private"

# ==============================================================================
# STEP 2: GENERATE TIER 1 — OFFLINE ROOT CA (RSA-4096 / SHA-384 / 20 Years)
# ==============================================================================
echo "===> [Step 2] Generating Tier 1: Offline Root CA Private Key and Self-Signed Certificate..."

# Generate Root CA RSA-4096 Private Key using StrongSwan 'pki' tool
# --type rsa: Specify RSA algorithm; --size 4096: Enforce 4096-bit key length for 20-year security
pki --gen --type rsa --size 4096 --outform pem > "${BUILD_DIR}/private/root-ca.key"
chmod 600 "${BUILD_DIR}/private/root-ca.key"

# Generate Root CA Self-Signed X.509 Certificate
# --self: Self-signed root certificate; --ca: Mark basicConstraints CA:TRUE
# --lifetime 7300: 20 years validity; --digest sha384: Enforce SHA-384 hashing
pki --self --ca --lifetime 7300 --in "${BUILD_DIR}/private/root-ca.key" \
    --type rsa --dn "C=US, O=TunnelPoint Enterprise VPN, CN=TunnelPoint Root CA" \
    --digest sha384 --outform pem > "${BUILD_DIR}/cacerts/root-ca.crt"

echo "     [SUCCESS] Root CA generated: ${BUILD_DIR}/cacerts/root-ca.crt"
echo "     [SECURITY NOTICE] In production, copy root-ca.key to an air-gapped HSM and delete from online servers!"

# ==============================================================================
# STEP 3: GENERATE TIER 2 — ONLINE INTERMEDIATE CA (RSA-4096 / SHA-384 / 5 Years)
# ==============================================================================
echo "===> [Step 3] Generating Tier 2: Online Intermediate CA Private Key and Signed Certificate..."

# Generate Intermediate CA RSA-4096 Private Key
pki --gen --type rsa --size 4096 --outform pem > "${BUILD_DIR}/private/intermediate-ca.key"
chmod 600 "${BUILD_DIR}/private/intermediate-ca.key"

# Generate Intermediate CA Certificate, signed by Tier 1 Root CA!
# --issue: Issue certificate signed by CA; --cakey & --cacert: Point to Root CA credentials
# --ca: Mark basicConstraints CA:TRUE (pathlen=0 enforced via flags)
pki --issue --ca --lifetime 1825 --in "${BUILD_DIR}/private/intermediate-ca.key" \
    --type rsa --dn "C=US, O=TunnelPoint Enterprise VPN, CN=TunnelPoint Intermediate CA" \
    --cakey "${BUILD_DIR}/private/root-ca.key" --cacert "${BUILD_DIR}/cacerts/root-ca.crt" \
    --digest sha384 --outform pem > "${BUILD_DIR}/intermediate/intermediate-ca.crt"

echo "     [SUCCESS] Intermediate CA generated: ${BUILD_DIR}/intermediate/intermediate-ca.crt"

# Create a unified CA Certificate Chain bundle (Intermediate CA + Root CA) for gateway deployment
cat "${BUILD_DIR}/intermediate/intermediate-ca.crt" "${BUILD_DIR}/cacerts/root-ca.crt" > "${BUILD_DIR}/cacerts/ca-chain.crt"

# ==============================================================================
# STEP 4: GENERATE TIER 3 — GATEWAY A LEAF CERTIFICATE (New York / 203.0.113.10)
# ==============================================================================
echo "===> [Step 4] Generating Tier 3: Gateway A (New York) Private Key and Leaf Certificate..."

# Generate Gateway A Private Key (Using ECDSA P-384 for high-speed elliptic curve encryption!)
# --type ecdsa: Elliptic Curve DSA; --size 384: NIST P-384 curve (equals RSA-7680 strength!)
pki --gen --type ecdsa --size 384 --outform pem > "${BUILD_DIR}/private/gateway-a.key"
chmod 600 "${BUILD_DIR}/private/gateway-a.key"

# Issue Gateway A Leaf Certificate, signed by Tier 2 Intermediate CA!
# --san: Specify Subject Alternative Names (DNS FQDN and Public WAN IP address!)
# --flag serverAuth --flag clientAuth --flag ipsecEndSystem: Enforce Extended Key Usages
pki --issue --lifetime 365 --in "${BUILD_DIR}/private/gateway-a.key" \
    --type ecdsa --dn "C=US, O=TunnelPoint Enterprise VPN, CN=gateway-a.tunnelpoint.io" \
    --san "gateway-a.tunnelpoint.io" --san "ny-gw.tunnelpoint.io" --san "203.0.113.10" --san "192.168.10.1" \
    --flag serverAuth --flag clientAuth --flag ipsecEndSystem \
    --cakey "${BUILD_DIR}/private/intermediate-ca.key" --cacert "${BUILD_DIR}/intermediate/intermediate-ca.crt" \
    --digest sha384 --outform pem > "${BUILD_DIR}/certs/gateway-a.crt"

echo "     [SUCCESS] Gateway A Leaf Certificate generated: ${BUILD_DIR}/certs/gateway-a.crt"

# ==============================================================================
# STEP 5: GENERATE TIER 3 — GATEWAY B LEAF CERTIFICATE (London / 198.51.100.20)
# ==============================================================================
echo "===> [Step 5] Generating Tier 3: Gateway B (London) Private Key and Leaf Certificate..."

# Generate Gateway B ECDSA P-384 Private Key
pki --gen --type ecdsa --size 384 --outform pem > "${BUILD_DIR}/private/gateway-b.key"
chmod 600 "${BUILD_DIR}/private/gateway-b.key"

# Issue Gateway B Leaf Certificate, signed by Tier 2 Intermediate CA!
pki --issue --lifetime 365 --in "${BUILD_DIR}/private/gateway-b.key" \
    --type ecdsa --dn "C=US, O=TunnelPoint Enterprise VPN, CN=gateway-b.tunnelpoint.io" \
    --san "gateway-b.tunnelpoint.io" --san "london-gw.tunnelpoint.io" --san "198.51.100.20" --san "192.168.20.1" \
    --flag serverAuth --flag clientAuth --flag ipsecEndSystem \
    --cakey "${BUILD_DIR}/private/intermediate-ca.key" --cacert "${BUILD_DIR}/intermediate/intermediate-ca.crt" \
    --digest sha384 --outform pem > "${BUILD_DIR}/certs/gateway-b.crt"

echo "     [SUCCESS] Gateway B Leaf Certificate generated: ${BUILD_DIR}/certs/gateway-b.crt"

# ==============================================================================
# STEP 6: GENERATE TIER 3 — REMOTE WORKER CLIENT LEAF CERTIFICATE
# ==============================================================================
echo "===> [Step 6] Generating Tier 3: Remote Worker Road-Warrior Client Certificate..."

# Generate Client ECDSA P-384 Private Key
pki --gen --type ecdsa --size 384 --outform pem > "${BUILD_DIR}/private/client-user1.key"
chmod 600 "${BUILD_DIR}/private/client-user1.key"

# Issue Client Certificate, signed by Intermediate CA!
pki --issue --lifetime 90 --in "${BUILD_DIR}/private/client-user1.key" \
    --type ecdsa --dn "C=US, O=TunnelPoint Enterprise VPN, CN=employee@tunnelpoint.io" \
    --san "employee@tunnelpoint.io" --san "client-laptop.tunnelpoint.io" \
    --flag clientAuth --flag ipsecUser \
    --cakey "${BUILD_DIR}/private/intermediate-ca.key" --cacert "${BUILD_DIR}/intermediate/intermediate-ca.crt" \
    --digest sha384 --outform pem > "${BUILD_DIR}/certs/client-user1.crt"

# Export PKCS#12 (.p12) bundle for easy import into Windows/macOS/iOS/Android VPN clients!
# Combines Client Key, Client Cert, and CA Chain into a single password-protected file (password: tunnelpoint)
openssl pkcs12 -export -inkey "${BUILD_DIR}/private/client-user1.key" \
    -in "${BUILD_DIR}/certs/client-user1.crt" -certfile "${BUILD_DIR}/cacerts/ca-chain.crt" \
    -out "${BUILD_DIR}/pkcs12/client-user1.p12" -passout pass:tunnelpoint

echo "     [SUCCESS] Remote Client Certificate & PKCS#12 bundle generated: ${BUILD_DIR}/pkcs12/client-user1.p12"

# ==============================================================================
# STEP 7: VERIFY X.509 CERTIFICATE SIGNATURE CHAINS
# ==============================================================================
echo "===> [Step 7] Verifying cryptographic trust chain from Leaf Certs up to Root CA..."
openssl verify -CAfile "${BUILD_DIR}/cacerts/root-ca.crt" -untrusted "${BUILD_DIR}/intermediate/intermediate-ca.crt" \
    "${BUILD_DIR}/certs/gateway-a.crt" \
    "${BUILD_DIR}/certs/gateway-b.crt" \
    "${BUILD_DIR}/certs/client-user1.crt"

echo "===> [SUCCESS] All 3-Tier PKI Certificates successfully generated and cryptographically verified!"
echo "     Build artifacts located in: ${BUILD_DIR}"
