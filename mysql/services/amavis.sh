#!/bin/sh

echo "*** Starting amavis.."
if [ ! -z ${DOMAIN} ]; then 
    sed -i "s/DOMAIN/${DOMAIN}/g" /etc/amavis/conf.d/50-user
    mv /var/lib/dkim/DOMAIN.pem /var/lib/dkim/${DOMAIN}.pem
fi

if [ ! -z ${HOSTNAME} ]; then 
    sed -i "s/HOSTNAME/${HOSTNAME}/g" /etc/amavis/conf.d/50-user
fi;

# Update password
. /opt/iredmail/.cv
sed -i "s/TEMP_AMAVISD_DB_PASSWD/$AMAVISD_DB_PASSWD/" /etc/clamav/clamd.conf /opt/iredapd/settings.py /opt/www/iredadmin/settings.py

logger DEBUG Starting amavisd-new
exec /usr/sbin/amavisd-new foreground
