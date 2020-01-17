#!/bin/sh
logger "*** Starting sogo..."

# Wait for MariaDB is up
while ! mysqladmin ping --silent; do sleep 1; done

# Load default variables
PIDFILE=/var/run/sogo/sogo.pid
LOGFILE=/var/log/sogo/sogo.log

. /etc/sysconfig/sogo
if [ -e /etc/default/sogo ]; then
  . /etc/default/sogo
fi

# Format options
DAEMON_OPTS="-WOWorkersCount $SOGO_WORKERS -WOPidFile $PIDFILE -WOLogFile $LOGFILE -WONoDetach YES"

# Manually change timezone based on attribute
if [ ! -z ${TIMEZONE} ]; then
    DAEMON_OPTS="$DAEMON_OPTS -WSOGoTimeZone $TIMEZONE"
fi
sed -i "/SOGoTimeZone/s#=.*#= $TZ;#" /etc/sogo/sogo.conf

# Update MySQL password
logger "Sogo update configuration files."
. /opt/iredmail/.cv
sed -i "s/TEMP_SOGO_DB_PASSWD/$SOGO_DB_PASSWD/g" /etc/sogo/sogo.conf
sed -i "s/TEMP_SOGO_SIEVE_MASTER_PASSWD/$SOGO_SIEVE_MASTER_PASSWD/g" /etc/sogo/sieve.cred

# # Traps for sogo stop
# trap_term_signal() {
#     killall $(cat $PIDFILE)
#     exit 0
# }

# trap_term_kill() {
#     kill -9 $(cat $PIDFILE)
#     exit 0
# }
# trap "trap_term_signal" TERM EXIT
# trap "trap_term_kill" KILL


# Start Sogo
# exec /usr/sbin/sogod ${DAEMON_OPTS}
exec gosu sogo /usr/sbin/sogod ${DAEMON_OPTS}
