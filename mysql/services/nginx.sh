#!/bin/sh
# Wait until Dovecot is started
while [ ! -f /var/tmp/postfix.run ]; do
  sleep 1
done
sleep 8
exec /usr/sbin/nginx -g "daemon off;"
