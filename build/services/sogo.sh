#!/bin/sh

echo "*** Starting sogo..."

. /etc/default/sogo
. /usr/share/GNUstep/Makefiles/GNUstep.sh

NAME=sogo
PIDFILE=/var/run/$NAME/$NAME.pid
LOGFILE=/var/log/$NAME/$NAME.log

# Overwrite prefork from attribut
if [ $SOGO_WORKERS -ne $PREFORK ];
    PREFORK=$SOGO_WORKERS
fi;

# Format options
DAEMON_OPTS="-WOWorkersCount $PREFORK -WOPidFile $PIDFILE -WOLogFile $LOGFILE -WONoDetach YES"

# Manually change timezone based on attribut
if [ ! -z ${TIMEZONE} ]; then 
    DAEMON_OPTS="$DAEMON_OPTS -WSOGoTimeZone $TIMEZONE"
fi


exec /sbin/setuser $NAME /usr/sbin/sogod -- $DAEMON_OPTS
