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
        #
        # sogod creates its own SQL storage tables (sogo_store,
        # sogo_folder_info, sogo_sessions_folder, sogo_user_profile, ...)
        # itself, but only in a one-shot check at daemon startup, never
        # retried later - supervisord starts programs in priority order but
        # does not wait for one to be *ready* before starting the next, so
        # sogod (priority after mariadb) can win the race against
        # mariadbd's own startup and find the socket refusing connections
        # on that first, only attempt. The tables then silently never
        # exist for the life of the container: SOGo login/webmail still
        # "work" (mail folders come from IMAP, not these tables), but every
        # Calendar/Contacts/ActiveSync folder and every session is broken
        # (found via `docker exec ... mysql -e "SHOW TABLES"` showing only
        # the `users` auth view - restarting sogod alone, once MariaDB was
        # already up, made them appear). `mysqladmin ping` in a wait loop
        # before exec'ing sogod is cheap and makes this deterministic
        # instead of a startup-order race - row 11/12's Calendar/Contacts
        # folders and CalDAV/CardDAV need it, ActiveSync's own folders too.
        execstart="/bin/sh -c 'for i in \$(seq 1 60); do mysqladmin ping -h 127.0.0.1 --silent 2>/dev/null && break; sleep 1; done; exec /usr/sbin/sogod -WONoDetach YES -WOWorkersCount 2 -WOPidFile /var/run/sogo/sogo.pid -WOLogFile /var/log/sogo/sogo.log'"
        user=sogo
    elif [ "$svc" = "dovecot" ]; then
        # Same startup race as sogod above, with a worse outcome: supervisord
        # starts dovecot and mariadbd together, and dovecot's auth worker
        # tries its SQL connection (127.0.0.1:3306) before MariaDB listens.
        # Since Debian's dovecot 1:2.4.1+dfsg1-6+deb13u7 (DSA-6526-1,
        # 2026-09-28; patch passdb_sql-connect-before-expanding-query-
        # variables) a passdb lookup no longer waits for that connection - it
        # fails at once ("Not connected to database") and a reconnect is
        # tried only when the next login arrives, with the delay multiplied
        # by 5 after every failure (1, 5, 25, 125, 625 s, capped at 1800 s,
        # SQL_CONNECT_MAX_DELAY in dovecot's lib-sql). Result: after a
        # container restart every IMAP/SMTP/ActiveSync login is refused with
        # "Temporary authentication failure" for minutes, up to 30. Before
        # deb13u7 the lookup waited and recovered within a minute, so the
        # race was invisible.
        #
        # Wait for MariaDB, then exec dovecot exactly as dovecot.service
        # does (`dovecot -F`). Unlike sogo there is deliberately NO cap on
        # the loop: starting dovecot anyway after N seconds would land in the
        # backoff above whenever MariaDB needs longer (InnoDB crash recovery
        # after an unclean stop can), whereas a dovecot that never starts
        # leaves 993 closed, the healthcheck turns unhealthy and the failure
        # is visible instead of a silent lockout. This only orders startup: a
        # MariaDB that supervisord restarts at runtime is not covered.
        execstart="/bin/sh -c 'until mysqladmin ping -h 127.0.0.1 --silent 2>/dev/null; do sleep 1; done; exec /usr/sbin/dovecot -F'"
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
