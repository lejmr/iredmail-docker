#!/bin/bash
# Docker HEALTHCHECK (row 1): healthy only once Postfix, Dovecot, MariaDB,
# nginx, SOGo and amavis all answer on their port. A plain TCP connect is enough -
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
# amavis: submission/smtps hand every message to it before answering DATA
# (smtpd_proxy_filter, image/Dockerfile), so until it listens - it loads
# SpamAssassin's rules first, longer than dovecot takes - every message
# sent is refused with "451 4.3.0 queue file write error". Not healthy
# before sending works.
check 10026 || exit 1

# Row 9 (virus): when ClamAV is on, the container isn't healthy until
# clamd has finished loading its signature database - clamd doesn't bind
# its control socket until that load completes, so this doubles as "the
# database is loaded", not just "the process is running" (freshclam's
# first download can take a while right after first start).
if [ "${CLAMAV:-1}" != "0" ]; then
    clamdscan --ping 1 >/dev/null 2>&1 || exit 1
fi

exit 0
