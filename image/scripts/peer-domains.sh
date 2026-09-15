#!/bin/bash
# PEER_DOMAINS="b.example=mail-b,c.example=mail-c" - lets two (or more)
# containers on the same docker network exchange mail without public DNS/MX
# lookups (used by the two-node compose.yaml at the repo root, and by rows
# 6/7/9 of ACCEPTANCE.md which need two servers). Regenerated on every
# start so it survives a restart or a changed PEER_DOMAINS.
set -euo pipefail

TRANSPORT=/etc/postfix/transport
: > "$TRANSPORT"
peer_ips=""
IFS=','
for pair in ${PEER_DOMAINS:-}; do
    [ -z "$pair" ] && continue
    domain="${pair%%=*}"
    host="${pair#*=}"
    echo "${domain}  smtp:[${host}]:25" >> "$TRANSPORT"
    ip="$(getent hosts "$host" 2>/dev/null | awk '{print $1; exit}')"
    [ -n "$ip" ] && peer_ips="${peer_ips} ${ip}/32"
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

# Trust the peer containers themselves (permit_mynetworks): without a
# public MX/A record for a peer's domain, B's own reject_unknown_sender_domain
# (smtpd_sender_restrictions) rejects A's mail with "450 4.1.8 ... Domain not
# found" - permit_mynetworks runs ahead of that check and skips it, same as
# it already skips smtpd_relay_restrictions for these containers. Rebuilt
# from a fixed base every start (not appended to the current value) so a
# peer's IP changing across a recreate never leaves a stale entry behind.
postconf -e "mynetworks = 127.0.0.0/8${peer_ips}"
