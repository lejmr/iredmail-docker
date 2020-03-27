#!/bin/bash

PIDFILE=/var/run/spamd.pid

# Load default variables
if [ -e /etc/sysconfig/spamassassin ]; then
  source /etc/sysconfig/spamassassin
fi

# Stop already running Spamasssin instance
if [ -e $PIDFILE ]; then
    if [ -e "/proc/$(cat $PIDFILE)/status" ]; then
        kill $(cat $PIDFILE)
    fi
fi

# Start Spamassasin
/sbin/portrelease spamd
exec /usr/bin/spamd --pidfile $PIDFILE $SPAMDOPTIONS

