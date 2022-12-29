#!/bin/sh

# Wait until database files created
while [ ! -e /var/lib/clamav/main.cvd ] && [ ! -e /var/lib/clamav/bytecode.cvd ] && [ ! -e /var/lib/clamav/daily.cvd ]; do
    sleep 1
done

logger "Checking for ClamAV updates"
/usr/bin/freshclam
sleep 3600