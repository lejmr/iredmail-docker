#!/bin/bash
# Build-time only: convert the systemd units iRedMail's installer already
# wrote/enabled (SYSTEMD_SERVICE_DIR=/lib/systemd/system, conf/global) into
# supervisord program stanzas, instead of re-guessing each daemon's
# foreground invocation by hand - the unit file already has it right.
#
# ponytail: naive `ExecStart=` line parser, not a systemd unit parser -
# good enough because we only read units iRedMail itself generated for a
# known, small service list. Upgrade if a future iRedMail unit uses
# ExecStart= more than once or %-specifiers.
set -euo pipefail

OUT=/etc/supervisor/conf.d/iredmail.conf
UNIT_DIRS="/lib/systemd/system /usr/lib/systemd/system /etc/systemd/system"
# order = start order (priority)
SERVICES="mariadb memcached postfix dovecot clamav-daemon clamav-freshclam amavis spamassassin iredapd sogo iredadmin nginx"

find_unit() {
    for d in $UNIT_DIRS; do
        [ -f "$d/$1.service" ] && { echo "$d/$1.service"; return 0; }
    done
    return 1
}

priority=100
{
echo "; generated at build time by build/gen-supervisord.sh from the"
echo "; systemd units iRedMail's installer wrote - do not hand-edit."
} > "$OUT"

for svc in $SERVICES; do
    unit="$(find_unit "$svc" || true)"
    [ -z "$unit" ] && continue

    if [ "$svc" = "nginx" ]; then
        execstart="/usr/sbin/nginx -g 'daemon off;'"
    elif [ "$svc" = "mariadb" ]; then
        execstart="/usr/sbin/mariadbd --user=mysql"
    else
        execstart="$(grep -m1 '^ExecStart=' "$unit" | sed 's/^ExecStart=//' || true)"
        # strip a leading '-' (systemd: ignore exit status marker)
        execstart="${execstart#-}"
    fi
    [ -z "$execstart" ] && continue

    user="$(grep -m1 '^User=' "$unit" | sed 's/^User=//' || true)"
    workdir="$(grep -m1 '^WorkingDirectory=' "$unit" | sed 's/^WorkingDirectory=//' || true)"

    priority=$((priority + 10))
    {
        echo ""
        echo "[program:${svc}]"
        echo "command=${execstart}"
        [ -n "$workdir" ] && echo "directory=${workdir}"
        [ -n "$user" ] && echo "user=${user}"
        echo "autostart=true"
        echo "autorestart=true"
        echo "startretries=10"
        echo "priority=${priority}"
        echo "stdout_logfile=/dev/stdout"
        echo "stdout_logfile_maxbytes=0"
        echo "stderr_logfile=/dev/stderr"
        echo "stderr_logfile_maxbytes=0"
    } >> "$OUT"
    echo "supervisord: added [program:${svc}] from ${unit}"
done

echo "--- generated $OUT ---"
cat "$OUT"
