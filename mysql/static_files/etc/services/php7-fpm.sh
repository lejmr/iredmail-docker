#!/bin/sh
# Wait until Dovecot is started
while ! nc -z localhost 993; do
  sleep 1
done


# Update RCB password
. /opt/iredmail/.cv
sed -i "s/TEMP_RCM_DB_PASSWD/$RCM_DB_PASSWD/" /opt/www/roundcubemail/config/config.inc.php \
    /opt/www/roundcubemail/plugins/password/config.inc.php

mkdir -p /run/php
exec /usr/sbin/php-fpm7.0 --nodaemonize --fpm-config /etc/php/7.0/fpm/php-fpm.conf
