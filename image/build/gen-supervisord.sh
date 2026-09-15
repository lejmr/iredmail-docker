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
SERVICES="rsyslog mariadb memcached postfix dovecot clamav-daemon clamav-freshclam amavis spamassassin iredapd sogo iredadmin nginx"

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
    user=""; workdir=""; unit=""

    if [ "$svc" = "nginx" ]; then
        execstart="/usr/sbin/nginx -g 'daemon off;'"
    elif [ "$svc" = "mariadb" ]; then
        execstart="/usr/sbin/mariadbd --user=mysql"
    elif [ "$svc" = "postfix" ]; then
        # ponytail: postfix.service's ExecStart is `postfix debian-systemd-start`,
        # a wrapper that refuses to run except under systemd ("the Postfix
        # mail system is started through systemd but not under systemd?").
        # `start-fg` is postfix's own supported foreground mode (postfix(1)),
        # not re-derived from the unit.
        execstart="/usr/sbin/postfix start-fg"
    elif [ "$svc" = "sogo" ]; then
        # ponytail: Debian's sogo package ships only /etc/init.d/sogo, no
        # systemd unit to read ExecStart= from - same DAEMON_OPTS as that
        # script, not re-derived.
        [ -f /etc/init.d/sogo ] || continue
        mkdir -p /var/run/sogo /var/spool/sogo /var/log/sogo
        chown sogo:sogo /var/run/sogo /var/spool/sogo /var/log/sogo
        # -WONoDetach YES: without it, sogod's watchdog double-forks and
        # detaches from whatever spawned it (supervisor sees a clean exit
        # 0 and considers the program "stopped", while the detached
        # workers linger holding port 20000 - the next autorestart then
        # fails to bind it).
        execstart="/usr/sbin/sogod -WONoDetach YES -WOWorkersCount 2 -WOPidFile /var/run/sogo/sogo.pid -WOLogFile /var/log/sogo/sogo.log"
        user=sogo
    elif [ "$svc" = "iredapd" ]; then
        # ponytail: iredapd.py self-daemonizes (libs/daemon.py double-fork)
        # unless --foreground is on argv - same detach-then-orphan failure
        # mode as sogo above (iredapd.py: `if '--foreground' not in
        # sys.argv: daemon.daemonize(...)`).
        unit="$(find_unit "$svc" || true)"
        mkdir -p /var/log/iredapd
        execstart="/usr/bin/python3 /opt/iredapd/iredapd.py --foreground"
    elif [ "$svc" = "iredadmin" ]; then
        unit="$(find_unit "$svc" || true)"
        [ -z "$unit" ] && continue
        mkdir -p /var/run/iredadmin
        execstart="$(grep -m1 '^ExecStart=' "$unit" | sed 's/^ExecStart=//' || true)"
        execstart="${execstart#-}"
        user="$(grep -m1 '^User=' "$unit" | sed 's/^User=//' || true)"
        workdir="$(grep -m1 '^WorkingDirectory=' "$unit" | sed 's/^WorkingDirectory=//' || true)"
    else
        unit="$(find_unit "$svc" || true)"
        [ -z "$unit" ] && continue
        execstart="$(grep -m1 '^ExecStart=' "$unit" | sed 's/^ExecStart=//' || true)"
        # strip a leading '-' (systemd: ignore exit status marker)
        execstart="${execstart#-}"
        user="$(grep -m1 '^User=' "$unit" | sed 's/^User=//' || true)"
        workdir="$(grep -m1 '^WorkingDirectory=' "$unit" | sed 's/^WorkingDirectory=//' || true)"
    fi
    [ -z "$execstart" ] && continue

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
    echo "supervisord: added [program:${svc}] from ${unit:-init.d/built-in}"
done

echo "--- generated $OUT ---"
cat "$OUT"
