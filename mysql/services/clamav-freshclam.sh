#!/bin/sh

# Wait until SOGo is started
while ! nc -z localhost 20000; do   
  sleep 1
done
sleep 10

exec /usr/bin/freshclam -d --quiet
