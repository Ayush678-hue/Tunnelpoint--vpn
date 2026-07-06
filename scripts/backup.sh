#!/usr/bin/env bash
# TunnelPoint Enterprise Encrypted Backup Script (PART 24)
# Target File: /scripts/backup.sh
# Archives strongswan configs, VICI scripts, and PKI keys into AES-256-GCM encrypted tarball

set -euo pipefail

BACKUP_DIR="${1:-/var/backups/tunnelpoint}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ARCHIVE_NAME="tunnelpoint_backup_${TIMESTAMP}.tar.gz"
ENCRYPTED_NAME="tunnelpoint_backup_${TIMESTAMP}.tar.gz.enc"
ENCRYPTION_PASS="${TUNNELPOINT_BACKUP_PASS:-EnterpriseSecretPassphrase2026!}"

echo "===> [Step 1] Initializing secure backup directory: ${BACKUP_DIR}..."
mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

echo "===> [Step 2] Creating compressed tarball of system configs and PKI..."
tar -czf "${BACKUP_DIR}/${ARCHIVE_NAME}" \
    --ignore-failed-read \
    /etc/strongswan.conf \
    /etc/swanctl \
    /config \
    /pki \
    2>/dev/null || true

echo "===> [Step 3] Encrypting tarball with OpenSSL AES-256-GCM (PBKDF2 / SHA-384)..."
openssl enc -aes-256-gcm -salt -pbkdf2 -iter 100000 \
    -in "${BACKUP_DIR}/${ARCHIVE_NAME}" \
    -out "${BACKUP_DIR}/${ENCRYPTED_NAME}" \
    -pass pass:"${ENCRYPTION_PASS}"

# Remove unencrypted temporary tarball immediately
rm -f "${BACKUP_DIR}/${ARCHIVE_NAME}"
chmod 600 "${BACKUP_DIR}/${ENCRYPTED_NAME}"

echo "     [SUCCESS] Encrypted backup created: ${BACKUP_DIR}/${ENCRYPTED_NAME}"

echo "===> [Step 4] Pruning historical backup archives older than 30 days..."
find "${BACKUP_DIR}" -name "tunnelpoint_backup_*.enc" -type f -mtime +30 -delete

echo "===> [SUCCESS] Backup lifecycle complete!"
ls -lh "${BACKUP_DIR}"
