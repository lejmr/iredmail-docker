#!/bin/sh

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
