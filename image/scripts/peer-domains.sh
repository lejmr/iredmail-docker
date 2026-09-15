#!/bin/bash
# PEER_DOMAINS="b.example=mail-b,c.example=mail-c" - lets two (or more)
# containers on the same docker network exchange mail without public DNS/MX
# lookups (used by the two-node compose.yaml at the repo root, and by rows
# 6/7/9 of ACCEPTANCE.md which need two servers). Regenerated on every
# start so it survives a restart or a changed PEER_DOMAINS.
set -euo pipefail

TRANSPORT=/etc/postfix/transport
: > "$TRANSPORT"
IFS=','
for pair in ${PEER_DOMAINS:-}; do
    [ -z "$pair" ] && continue
    domain="${pair%%=*}"
    host="${pair#*=}"
    echo "${domain}  smtp:[${host}]:25" >> "$TRANSPORT"
done
unset IFS

postmap "$TRANSPORT"

# Prepend our peer table to whatever transport_maps iRedMail already
# configured (its own MySQL-backed maps), instead of replacing it -
# idempotent across restarts.
current="$(postconf -h transport_maps 2>/dev/null || true)"
case "$current" in
    "hash:${TRANSPORT}"*) : ;; # already first in the list
    *) postconf -e "transport_maps = hash:${TRANSPORT}, ${current}" ;;
esac
