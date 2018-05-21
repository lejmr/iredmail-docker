#!/bin/sh

### Wait until postfix is started
while [ ! -f /var/tmp/postfix.run ]; do
  sleep 1
done


echo "*** Starting mlmmjadmin.."
. /opt/iredmail/.cv
if [ ! -z ${VMAIL_DB_ADMIN_PASSWD} ]; then 
    sed -i "s/TEMP_VMAIL_DB_ADMIN_PASSWD/${VMAIL_DB_ADMIN_PASSWD}/g" /opt/mlmmjadmin/settings.py
fi

logger DEBUG configure mlmmjadmin api_auth
RS=$(echo $RANDOM | md5sum | awk '{print $1}')
sed -i "s/^api_auth_tokens.*$/api_auth_tokens = ['$RS']/g"  /opt/mlmmjadmin/settings.py
sed -i "s/^backend_api.*$/backend_api = 'bk_iredmail_sql'/g"  /opt/mlmmjadmin/settings.py


logger DEBUG mlmmjadmin
/bin/mkdir -p /var/run/mlmmjadmin
chown mlmmj:mlmmj /var/run/mlmmjadmin
/bin/chmod 0755 /var/run/mlmmjadmin
exec /usr/bin/uwsgi --ini /opt/mlmmjadmin/rc_scripts/uwsgi/debian.ini --pidfile /var/run/mlmmjadmin/mlmmjadmin.pid
