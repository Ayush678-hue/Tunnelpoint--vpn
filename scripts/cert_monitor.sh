#!/usr/bin/env bash
# TunnelPoint Automated PKI Certificate Expiration Monitor (PART 24)
# Target File: /scripts/cert_monitor.sh
# Scans /etc/swanctl/x509/ and /pki/build/certs/ for expiring certificates and alerts via syslog

set -uo pipefail

CERT_DIRS=("/etc/swanctl/x509" "/pki/build/certs" "/pki/build/cacerts")
ALERT_THRESHOLD_DAYS=30
CURRENT_EPOCH=$(date +%s)
STATUS=0

echo "=============================================================================="
echo "       TUNNELPOINT PKI CERTIFICATE EXPIRATION AUDIT                           "
echo "=============================================================================="

for dir in "${CERT_DIRS[@]}"; do
    if [ ! -d "${dir}" ]; then
        continue
    fi

    for cert in "${dir}"/*.crt "${dir}"/*.pem; do
        if [ ! -f "${cert}" ]; then
            continue
        fi

        # Extract certificate Subject Common Name (CN) and expiration date
        CN=$(openssl x509 -in "${cert}" -noout -subject | sed -n 's/.*CN = \([^,]*\).*/\1/p' || echo "Unknown")
        END_DATE_STR=$(openssl x509 -in "${cert}" -noout -enddate | cut -d= -f2)
        
        # Convert date to Unix epoch (cross-compatible date conversion)
        END_EPOCH=$(date -d "${END_DATE_STR}" +%s 2>/dev/null || date -jf "%b %d %T %Y %Z" "${END_DATE_STR}" +%s 2>/dev/null || echo 0)
        
        if [ "${END_EPOCH}" -eq 0 ]; then
            continue
        fi

        REMAINING_SECONDS=$((END_EPOCH - CURRENT_EPOCH))
        REMAINING_DAYS=$((REMAINING_SECONDS / 86400))

        if [ "${REMAINING_DAYS}" -le 0 ]; then
            echo "[ CRITICAL ] Certificate EXPIRED! File: ${cert} (CN: ${CN}) expired ${REMAINING_DAYS} days ago!"
            logger -p auth.crit "TunnelPoint PKI ALERT: Certificate ${CN} in ${cert} is EXPIRED!"
            STATUS=2
        elif [ "${REMAINING_DAYS}" -le "${ALERT_THRESHOLD_DAYS}" ]; then
            echo "[ WARNING  ] Certificate EXPIRING SOON! File: ${cert} (CN: ${CN}) expires in ${REMAINING_DAYS} days!"
            logger -p auth.warning "TunnelPoint PKI WARNING: Certificate ${CN} expires in ${REMAINING_DAYS} days!"
            if [ ${STATUS} -lt 1 ]; then STATUS=1; fi
        else
            echo "[ OK       ] Certificate Healthy: ${cert} (CN: ${CN}) — Expires in ${REMAINING_DAYS} days."
        fi
    done
done

echo "=============================================================================="
exit ${STATUS}
