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

exit 0
