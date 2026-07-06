#!/usr/bin/env python3
"""
TunnelPoint StrongSwan VICI Prometheus Exporter (PART 21)
Target File: /monitoring/exporter/strongswan_exporter.py
Connects to /var/run/charon.vici Unix socket, extracts live IKE/IPsec SA metrics, and exports on port 9876.
"""

import sys
import time
import logging
from prometheus_client import start_http_server, Gauge, Counter
import vici

# Configure Logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("strongswan_exporter")

# ==============================================================================
# PROMETHEUS METRIC DEFINITIONS
# ==========================================
UP_STATUS = Gauge("strongswan_up_status", "StrongSwan charon daemon status (1 = UP, 0 = DOWN)")
IKE_SA_ACTIVE = Gauge("strongswan_ike_sa_active", "Number of active Phase 1 IKE_SAs", ["connection"])
CHILD_SA_ACTIVE = Gauge("strongswan_child_sa_active", "Number of active Phase 2 CHILD_SAs", ["connection", "child"])

TUNNEL_BYTES_IN = Gauge("strongswan_tunnel_bytes_in_total", "Inbound encrypted payload bytes", ["connection", "child"])
TUNNEL_BYTES_OUT = Gauge("strongswan_tunnel_bytes_out_total", "Outbound encrypted payload bytes", ["connection", "child"])
TUNNEL_PACKETS_IN = Gauge("strongswan_tunnel_packets_in_total", "Inbound encrypted payload packets", ["connection", "child"])
TUNNEL_PACKETS_OUT = Gauge("strongswan_tunnel_packets_out_total", "Outbound encrypted payload packets", ["connection", "child"])

REKEY_TIME_SECONDS = Gauge("strongswan_sa_rekey_time_seconds", "Seconds remaining until next SA rekey", ["connection"])

def collect_metrics():
    """Connects to StrongSwan VICI socket and updates Prometheus gauges."""
    try:
        session = vici.Session(sock_path="/var/run/charon.vici")
        UP_STATUS.set(1)
        logger.debug("Successfully connected to StrongSwan VICI socket.")
        
        # Reset counts
        active_ike = 0
        active_child = 0
        
        # Query active Security Associations
        for sas in session.list_sas():
            for conn_name, ike_sa in sas.items():
                active_ike += 1
                IKE_SA_ACTIVE.labels(connection=conn_name).set(1)
                
                # Extract rekey time if available
                rekey_time = ike_sa.get("rekey-time", 0)
                if rekey_time:
                    REKEY_TIME_SECONDS.labels(connection=conn_name).set(int(rekey_time))
                
                # Iterate through Phase 2 CHILD_SAs
                child_sas = ike_sa.get("child-sas", {})
                for child_name, child_sa in child_sas.items():
                    active_child += 1
                    CHILD_SA_ACTIVE.labels(connection=conn_name, child=child_name).set(1)
                    
                    bytes_in = int(child_sa.get("bytes-in", 0))
                    bytes_out = int(child_sa.get("bytes-out", 0))
                    pkts_in = int(child_sa.get("packets-in", 0))
                    pkts_out = int(child_sa.get("packets-out", 0))
                    
                    TUNNEL_BYTES_IN.labels(connection=conn_name, child=child_name).set(bytes_in)
                    TUNNEL_BYTES_OUT.labels(connection=conn_name, child=child_name).set(bytes_out)
                    TUNNEL_PACKETS_IN.labels(connection=conn_name, child=child_name).set(pkts_in)
                    TUNNEL_PACKETS_OUT.labels(connection=conn_name, child=child_name).set(pkts_out)
                    
        session.close()
    except Exception as e:
        logger.error(f"Failed to connect to StrongSwan VICI socket: {e}")
        UP_STATUS.set(0)

def main():
    port = 9876
    logger.info(f"Starting TunnelPoint StrongSwan Prometheus Exporter on port {port}...")
    start_http_server(port)
    while True:
        collect_metrics()
        time.sleep(15)

if __name__ == "__main__":
    main()
