#!/bin/bash
set -euo pipefail
. /usr/local/lib/iredmail/common.sh

require_mountpoints

if [ ! -f "${SECRETS_DIR}/.initialized" ]; then
    /usr/local/lib/iredmail/first-start.sh
fi

# row 13/#84: /etc and /opt are NOT volumes - a new container (plain
# `docker compose down` + `up`, or an upgrade) always starts from the
# image's pristine TEMP_*_PASSWD / build.invalid config, no matter what
# .initialized (on the /data/secrets volume) says. Re-render every start,
# not only first boot - see render-config.sh for what broke without this
# (every technical account's MariaDB auth, plus the TLS cert symlinks).
/usr/local/lib/iredmail/render-config.sh

# CLAMAV=0 (default, decision 3): iRedMail cannot skip installing ClamAV at
# install time, so it is disabled at runtime instead - its two supervisord
# programs are turned off and Amavis is routed around it (no @av_scanners
# entry left enabled referencing clamd).
CLAMAV="${CLAMAV:-0}"
CLAMAV_TOGGLE=/etc/supervisor/conf.d/zz-clamav-toggle.conf
if [ "$CLAMAV" = "0" ]; then
    {
        echo "[program:clamav-daemon]"
        echo "autostart=false"
        echo ""
        echo "[program:clamav-freshclam]"
        echo "autostart=false"
    } > "$CLAMAV_TOGGLE"
    sed -i "s/^\(\s*\['ClamAV::Daemon'.*\)$/#\1/" /etc/amavis/conf.d/15-content_filter_mode 2>/dev/null || true
else
    rm -f "$CLAMAV_TOGGLE"
    # /var/run/clamav (clamd.conf: LocalSocket /var/run/clamav/clamd.ctl)
    # only ever gets created by systemd-tmpfiles from the package's
    # RuntimeDirectory= unit setting, which never runs under supervisord -
    # without it clamd logs "Socket file ... could not be bound: No such
    # file or directory" and never actually comes up, so CLAMAV=1 silently
    # did nothing even though supervisor showed it RUNNING.
    mkdir -p /var/run/clamav
    chown clamav:clamav /var/run/clamav
fi

/usr/local/lib/iredmail/peer-domains.sh

# overrides/ volume (row 18): the smallest mechanism that survives an
# upgrade - Postfix gets `postconf -e` from key=value files, Dovecot gets a
# mounted directory Dovecot's own config already !include_try's.
/usr/local/lib/iredmail/apply-overrides.sh

# forward migrations (legacy mysql/upgrades/ idea, kept as the `versions`
# table + numbered scripts) - a no-op today, the hook for the next image.
/usr/local/lib/iredmail/migrate.sh

# `postfix check` creates/repairs the whole queue directory tree (incl.
# /var/spool/postfix/private, where Dovecot's auth and lmtp sockets bind)
# with correct ownership *before* supervisord starts anything. Without
# this, supervisord launches postfix and dovecot together and dovecot
# loses the race the first time /var/spool/postfix/private does not exist
# yet ("bind(.../dovecot-auth) failed: No such file or directory") - it
# self-heals via autorestart, but leaves Error: lines in the startup log
# (row 1: no `error` at startup). Warns (harmless: postqueue/postdrop
# setgid bits, unrelated to this path) but never fails.
postfix check || true

exec "$@"
