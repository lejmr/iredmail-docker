#!/bin/sh

# Update MySQL password
. /opt/iredmail/.cv
DOMAIN=$(hostname -d)
sed -i "s/TEMP_IREDADMIN_DB_PASSWD/$IREDADMIN_DB_PASSWD/" /opt/www/iredadmin/settings.py
sed -i "s/TEMP_IREDAPD_DB_PASSWD/$IREDAPD_DB_PASSWD/" /opt/www/iredadmin/settings.py
sed -i "s/TEMP_VMAIL_DB_ADMIN_PASSWD/$VMAIL_DB_ADMIN_PASSWD/" /opt/www/iredadmin/settings.py
sed -i "s/DOMAIN/${DOMAIN}/g" /opt/www/iredadmin/settings.py

# Starting procedure based on SystemD service:
# /lib/systemd/system/iredadmin.service
mkdir /var/run/iredadmin
chown iredadmin:iredadmin /var/run/iredadmin
chmod 0755 /var/run/iredadmin

# start - listens on tcp/7791
exec /usr/sbin/uwsgi --ini /opt/www/iredadmin/rc_scripts/uwsgi/rhel.ini --pidfile /var/run/iredadmin/iredadmin.pid
