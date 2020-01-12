#!/bin/sh

if [ ! -e /var/lib/clamav/main.cvd ]; then
   echo "*** Preparing ClamAV files"
   logger Downloading ClamAV files: main.cvd
   wget -P /var/lib/clamav -nv http://database.clamav.net/main.cvd

   logger Downloading ClamAV files: bytecode.cvd
   wget -P /var/lib/clamav -nv http://database.clamav.net/bytecode.cvd

   logger Downloading ClamAV files: daily.cvd
   wget -P /var/lib/clamav -nv http://database.clamav.net/daily.cvd
fi

chown -R clamupdate:virusgroup /var/lib/clamav
# install -o clamav -g clamav -d /var/run/clamav

logger Starting ClamAV deamon.
exec /usr/sbin/clamd -c /etc/clamd.d/amavisd.conf -F
