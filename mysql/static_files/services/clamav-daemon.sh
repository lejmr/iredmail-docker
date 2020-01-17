#!/bin/sh

# Refresh ClamAV cvd files
/usr/bin/freshclam

chown -R clamupdate:virusgroup /var/lib/clamav
# install -o clamav -g clamav -d /var/run/clamav

logger Starting ClamAV deamon.
exec /usr/sbin/clamd -c /etc/clamd.d/amavisd.conf -F
