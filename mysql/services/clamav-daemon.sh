#!/bin/sh

if [ ! -e /var/lib/clamav/main.cvd ]; then
   echo "*** Preparing ClamAV files"
   wget -P /var/lib/clamav -nv http://database.clamav.net/main.cvd
   wget -P /var/lib/clamav -nv http://database.clamav.net/bytecode.cvd
   wget -P /var/lib/clamav -nv http://database.clamav.net/daily.cvd
fi

chown -R clamav:clamav /var/lib/clamav
install -o clamav -g clamav -d /var/run/clamav

exec /usr/sbin/clamd
