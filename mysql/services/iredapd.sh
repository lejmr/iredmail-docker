#!/bin/sh

# Configure plugins
if [ ! -z "${IREDAPD_PLUGINS}" ]; then
  echo "*** Configuring iredapd";
  sed -i "/^plugins /c plugins = $IREDAPD_PLUGINS" /opt/iredapd/settings.py;
fi

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

rm -rf /var/run/iredapd.pid
/etc/init.d/iredapd start

while [ ! -f /var/run/iredapd.pid ]
do
    sleep 1
done

pid=$(cat /var/run/iredapd.pid)

while kill -0 $pid 2>/dev/null
do
    sleep 1
done
