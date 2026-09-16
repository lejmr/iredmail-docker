#!/bin/bash
# Docker HEALTHCHECK (row 1): healthy only once Postfix, Dovecot, MariaDB,
# nginx and SOGo all answer on their port. A plain TCP connect is enough -
# this is a liveness probe, not another copy of the acceptance suite.
set -u

check() {
    timeout 2 bash -c "exec 3<>/dev/tcp/127.0.0.1/$1" 2>/dev/null
}

check 25   || exit 1   # postfix
check 993  || exit 1   # dovecot imaps
check 3306 || exit 1   # mariadb
check 443  || exit 1   # nginx
check 20000 || exit 1  # sogo (proxied by nginx, but checked directly too)

# Row 9 (virus): when ClamAV is on, the container isn't healthy until
# clamd has finished loading its signature database - clamd doesn't bind
# its control socket until that load completes, so this doubles as "the
# database is loaded", not just "the process is running" (freshclam's
# first download can take a while right after first start).
if [ "${CLAMAV:-1}" != "0" ]; then
    clamdscan --ping 1 >/dev/null 2>&1 || exit 1
fi

exit 0
