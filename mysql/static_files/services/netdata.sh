#!/bin/sh

### Wait until postfix is started
echo "*** Starting Netdata.."
DOMAIN=$(hostname -d)
if [ ! -z ${DOMAIN} ]; then 
    echo "postmaster@${DOMAIN}:${POSTMASTER_PASSWORD}" > /etc/nginx/netdata.users
fi

/bin/mkdir -p /opt/netdata/var/cache/netdata

logger DEBUG Starting amavisd-new
exec /opt/netdata/usr/sbin/netdata -P /run/netdata/netdata.pid -D
