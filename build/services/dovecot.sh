#!/bin/sh

if [ ! -z ${DOMAIN} ]; then 
    sed -i "s/DOMAIN/${DOMAIN}/g" /etc/dovecot/dovecot.conf
fi

echo "*** Starting dovecot.."
logger DEBUG Starting dovecot
exec /usr/sbin/dovecot -F -c /etc/dovecot/dovecot.conf
