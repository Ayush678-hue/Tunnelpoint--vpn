#!/usr/bin/env bash
# TunnelPoint Automated Health Check & Monitoring Script (PART 24)
# Target File: /scripts/health_check.sh
# Checks charon process, VICI socket, active SAs, kernel XFRM state, and ping connectivity

set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=============================================================================="
echo "            TUNNELPOINT ENTERPRISE GATEWAY HEALTH AUDIT                       "
echo "=============================================================================="

STATUS=0

# 1. Check if charon daemon process is running
if pgrep -x "charon" >/dev/null; then
    echo -e "[ ${GREEN}PASS${NC} ] StrongSwan charon IKEv2 daemon is running (PID: $(pgrep -x charon))."
else
    echo -e "[ ${RED}FAIL${NC} ] StrongSwan charon daemon is NOT running!"
    STATUS=1
fi

# 2. Check VICI socket responsiveness
if swanctl --stats >/dev/null 2>&1; then
    echo -e "[ ${GREEN}PASS${NC} ] VICI Unix domain socket (/var/run/charon.vici) is responsive."
else
    echo -e "[ ${RED}FAIL${NC} ] VICI Unix domain socket is unresponsive!"
    STATUS=1
fi

# 3. Check for active Security Associations (SAs)
ACTIVE_SAS=$(swanctl --list-sas | grep -c "INSTALLED" || true)
if [ "${ACTIVE_SAS}" -gt 0 ]; then
    echo -e "[ ${GREEN}PASS${NC} ] Active Phase 2 CHILD_SAs detected: ${ACTIVE_SAS} tunnel(s) installed."
else
    echo -e "[ ${YELLOW}WARN${NC} ] No active Phase 2 CHILD_SAs currently installed!"
    STATUS=2
fi

# 4. Check Linux Kernel XFRM State Database
XFRM_COUNT=$(ip xfrm state | grep -c "src" || true)
if [ "${XFRM_COUNT}" -gt 0 ]; then
    echo -e "[ ${GREEN}PASS${NC} ] Linux kernel XFRM SAD table populated with ${XFRM_COUNT} security association(s)."
else
    echo -e "[ ${YELLOW}WARN${NC} ] Linux kernel XFRM SAD table is empty!"
    STATUS=2
fi

# 5. Check Virtual Tunnel Interface (vti0) status
if ip link show dev vti0 >/dev/null 2>&1; then
    echo -e "[ ${GREEN}PASS${NC} ] Virtual Tunnel Interface vti0 is present and UP."
else
    echo -e "[ ${YELLOW}WARN${NC} ] Virtual Tunnel Interface vti0 does not exist!"
fi

echo "=============================================================================="
if [ ${STATUS} -eq 0 ]; then
    echo -e "       SYSTEM HEALTH STATUS: ${GREEN}100% HEALTHY & OPERATIONAL${NC}"
    exit 0
elif [ ${STATUS} -eq 2 ]; then
    echo -e "       SYSTEM HEALTH STATUS: ${YELLOW}WARNING — DEGRADED TUNNEL STATE${NC}"
    exit 0
else
    echo -e "       SYSTEM HEALTH STATUS: ${RED}CRITICAL FAILURE DETECTED${NC}"
    exit 1
fi
