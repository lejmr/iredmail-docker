#!/bin/sh

logger DEBUG Starting dovecot
exec /usr/sbin/dovecot -F -c /etc/dovecot/dovecot.conf
