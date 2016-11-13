#!/bin/sh
# Wait until SOGo is started
while ! nc -z localhost 20000; do   
  sleep 1
done
sleep 3

if [ ! -e /var/lib/clamav/main.cvd ]; then
   echo "*** Preparing ClamAV files.." 
   cd / && tar jxf /root/clamav.tar.bz2
   rm /root/clamav.tar.bz2
fi;

mkdir -p /var/run/clamav 
chown clamav:clamav /var/run/clamav
exec /usr/sbin/clamd
