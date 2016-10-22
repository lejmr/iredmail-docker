#!/bin/sh

echo "*** Starting sogo..."

. /etc/default/sogo
. /usr/share/GNUstep/Makefiles/GNUstep.sh

NAME=sogo
PIDFILE=/var/run/$NAME/$NAME.pid
LOGFILE=/var/log/$NAME/$NAME.log
DAEMON_OPTS="-WOWorkersCount $PREFORK -WOPidFile $PIDFILE -WOLogFile $LOGFILE -WONoDetach YES"

exec /sbin/setuser $NAME /usr/sbin/sogod -- $DAEMON_OPTS
