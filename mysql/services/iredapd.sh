#!/bin/sh

# COnfigurations
PROG='iredapd'
BINPATH='/opt/iredapd/iredapd.py'
PIDFILE='/var/run/iredapd.pid'

# Configure plugins
if [ ! -z "${IREDAPD_PLUGINS}" ]; then
  echo "*** Configuring iredapd";
  sed -i "/^plugins /c plugins = $IREDAPD_PLUGINS" /opt/iredapd/settings.py;
fi

check_status() {
    # Usage: check_status pid_number
    PID="${1}"
    l=$(ps -p ${PID} | wc -l | awk '{print $1}')
    if [ X"$l" = X"2" ]; then
        echo "running"
    else
        echo "stopped"
    fi
}

### Wait until postfix is started
while [ ! -f /var/tmp/postfix.run ]; do
  sleep 1
done

# Update MySQL password
. /opt/iredmail/.cv
sed -i "s/TEMP_IREDAPD_DB_PASSWD/$IREDAPD_DB_PASSWD/" /opt/iredapd/settings.py
sed -i "s/TEMP_VMAIL_DB_BIND_PASSWD/$VMAIL_DB_BIND_PASSWD/" /opt/iredapd/settings.py

trap_term_signal() {
    echo "Stopping (from SIGTERM)"
    kill -15 $pid
    while cat /proc/"$pid"/status | grep State: | grep -q zombie; test $? -gt 0
    do
        sleep 1
    done
    exit 0
}

trap "trap_term_signal" TERM


if [ -f ${PIDFILE} ]; then
  PID="$(cat ${PIDFILE})"
  s="$(check_status ${PID})"

  if [ X"$s" = X"running" ]; then
    echo "${PROG} is already running."
    kill -15 $PID
    rm -f ${PIDFILE} >/dev/null 2>&1
  else
    rm -f ${PIDFILE} >/dev/null 2>&1
  fi
fi

# Start iredapd
python ${BINPATH}


while [ ! -f /var/run/iredapd.pid ]
do
    sleep 1
done

pid=$(cat /var/run/iredapd.pid)

while kill -0 $pid 2>/dev/null
do
    sleep 1
done
