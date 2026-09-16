#!/bin/bash
# Row 18: apply /data/overrides/* on every start, before services come up,
# so an override survives both a restart and an image upgrade (it lives on
# the volume, never in a layer). Two mechanisms only - one per config
# format iRedMail already uses:
#
#   /data/overrides/postfix/main.cf.d/*.cf   "key = value" lines,
#                                             applied with `postconf -e`.
#   /data/overrides/dovecot/*.conf           Dovecot config snippets;
#                                             dovecot.conf already carries
#                                             `!include_try /data/overrides/dovecot/*.conf`
#                                             (added once, at build time).
set -euo pipefail

if [ -d /data/overrides/postfix/main.cf.d ]; then
    for f in /data/overrides/postfix/main.cf.d/*.cf; do
        [ -e "$f" ] || continue
        while IFS= read -r line; do
            case "$line" in ''|'#'*) continue ;; esac
            postconf -e "$line"
        done < "$f"
    done
fi
# Dovecot: nothing to do here, it re-reads /data/overrides/dovecot/*.conf
# itself via !include_try on every (re)start.
exit 0
