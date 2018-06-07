#!/bin/sh

### Wait until postfix is started
while [ ! -f /var/tmp/postfix.run ]; do
  sleep 1
done

echo "*** Starting amavis.."


#  Load configuration values
. /opt/iredmail/.cv
DOMAIN=$(hostname -d)
HOSTNAME=$(hostname -s)

sed -i "s/TEMP_AMAVISD_DB_PASSWD/$AMAVISD_DB_PASSWD/" /etc/clamav/clamd.conf \
    /opt/iredapd/settings.py \
    /etc/amavis/conf.d/50-user \
    /opt/www/iredadmin/settings.py
sed -i "s/HOSTNAME/${HOSTNAME}/g" /etc/amavis/conf.d/50-user
sed -i "s/DOMAIN/${DOMAIN}/g" /etc/amavis/conf.d/50-user

# If the rsa key is missing, generate it
if [ ! -e /var/lib/dkim/${DOMAIN}.pem ]; then
    logger DEBUG generating DKIM
    amavisd-new genrsa /var/lib/dkim/${DOMAIN}.pem 2048
    chown amavis:amavis /var/lib/dkim/${DOMAIN}.pem
    chmod 0400 /var/lib/dkim/${DOMAIN}.pem
fi


logger DEBUG Starting amavisd-new
exec /usr/sbin/amavisd-new foreground
