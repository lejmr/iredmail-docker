#!/bin/sh

mkdir -p /var/run/clamav 
chown clamav:clamav /var/run/clamav
exec /usr/sbin/clamd
