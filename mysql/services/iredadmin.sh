#!/bin/sh

trap_hup_signal() {
    echo "Reloading (from SIGHUP)"
    /etc/init.d/uwsgi reload
}

trap_term_signal() {
    echo "Stopping (from SIGTERM)"
    kill -3 $pid
    while cat /proc/"$pid"/status | grep State: | grep -q zombie; test $? -gt 0
    do
        sleep 1
    done
    exit 0
}

trap "trap_hup_signal" HUP
trap "trap_term_signal" TERM

rm -rf /run/uwsgi/app/iredadmin/pid
/etc/init.d/uwsgi start

while [ ! -f /run/uwsgi/app/iredadmin/pid ]
do
    sleep 1
done

pid=$(cat /run/uwsgi/app/iredadmin/pid)

while kill -0 $pid 2>/dev/null
do
    sleep 1
done
