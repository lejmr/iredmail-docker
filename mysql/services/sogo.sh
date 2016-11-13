#!/bin/sh

# Wait until Dovecot is started
while ! nc -z localhost 993; do   
  sleep 1
done

echo "*** Starting sogo..."

. /etc/default/sogo
. /usr/share/GNUstep/Makefiles/GNUstep.sh

NAME=sogo
PIDFILE=/var/run/$NAME/$NAME.pid
LOGFILE=/var/log/$NAME/$NAME.log

# Overwrite prefork from attribut
if [ ! -z ${SOGO_WORKERS} ]; then
    if [ $SOGO_WORKERS -ne $PREFORK ]; then
        PREFORK=$SOGO_WORKERS
    fi;
fi;

# Format options
DAEMON_OPTS="-WOWorkersCount $PREFORK -WOPidFile $PIDFILE -WOLogFile $LOGFILE -WONoDetach YES"

# Manually change timezone based on attribut
if [ ! -z ${TIMEZONE} ]; then 
    DAEMON_OPTS="$DAEMON_OPTS -WSOGoTimeZone $TIMEZONE"
fi


# Update MySQL password
. /opt/iredmail/.cv
sed -i "s/TEMP_SOGO_DB_PASSWD/$SOGO_DB_PASSWD/" /etc/sogo/sogo.conf
sed -i "s/TEMP_SOGO_SIEVE_MASTER_PASSWD/$SOGO_SIEVE_MASTER_PASSWD/" /etc/sogo/sieve.cred


exec /sbin/setuser $NAME /usr/sbin/sogod -- $DAEMON_OPTS
