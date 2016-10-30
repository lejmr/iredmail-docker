#!/bin/sh
# /var/lib/clamav/main.cvd

if [ ! -e /var/lib/clamav/main.cvd ]; then
   echo "*** Preparing ClamAV files.." 
   cd / && tar jxf /root/clamav.tar.bz2
   rm /root/clamav.tar.bz2
fi;

mkdir -p /var/run/clamav 
chown clamav:clamav /var/run/clamav
exec /usr/sbin/clamd
