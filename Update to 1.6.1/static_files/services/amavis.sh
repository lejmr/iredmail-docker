#!/bin/sh
echo "*** Starting amavis.."

#  Load configuration values
. /opt/iredmail/.cv
DOMAIN=$(hostname -d)
HOSTNAME=$(hostname -s)

# Workaround
ln -s /etc/amavisd/amavisd.conf /etc/amavisd.conf

sed -i "s/TEMP_AMAVISD_DB_PASSWD/$AMAVISD_DB_PASSWD/" /opt/iredapd/settings.py \
    /etc/amavisd/amavisd.conf \
    /opt/www/iredadmin/settings.py
sed -i "s/HOSTNAME/${HOSTNAME}/g" /etc/amavisd/amavisd.conf
sed -i "s/DOMAIN/${DOMAIN}/g" /etc/amavisd/amavisd.conf

# If the rsa key is missing, generate it
if [ ! -e /var/lib/dkim/${DOMAIN}.pem ]; then
    logger DEBUG generating DKIM
    amavisd genrsa /var/lib/dkim/${DOMAIN}.pem 2048
    chown amavis:amavis /var/lib/dkim/${DOMAIN}.pem
    chmod 0400 /var/lib/dkim/${DOMAIN}.pem
fi

logger DEBUG Starting amavisd
exec /usr/sbin/amavisd -c /etc/amavisd/amavisd.conf foreground
