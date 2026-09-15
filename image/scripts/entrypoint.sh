#!/bin/bash
set -euo pipefail
. /usr/local/lib/iredmail/common.sh

require_mountpoints

if [ ! -f "${SECRETS_DIR}/.initialized" ]; then
    /usr/local/lib/iredmail/first-start.sh
fi

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
fi

/usr/local/lib/iredmail/peer-domains.sh

# overrides/ volume (row 18): the smallest mechanism that survives an
# upgrade - Postfix gets `postconf -e` from key=value files, Dovecot gets a
# mounted directory Dovecot's own config already !include_try's.
/usr/local/lib/iredmail/apply-overrides.sh

# forward migrations (legacy mysql/upgrades/ idea, kept as the `versions`
# table + numbered scripts) - a no-op today, the hook for the next image.
/usr/local/lib/iredmail/migrate.sh

exec "$@"
