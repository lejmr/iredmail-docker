#!/bin/bash

echo "+++ Backing up SoGo database"
mysqldump sogo -r /var/vmail/backup/mysql/sogo.sql

echo +++ Stop SoGo
mv /etc/service/sogo/run /etc/service/sogo/run.backup
touch /tmp/sogo_stop
echo '#!/bin/bash' > /etc/service/sogo/run
echo "while [ -e /tmp/sogo_stop ]; do sleep 1; done" >> /etc/service/sogo/run
chmod +x /etc/service/sogo/run
killall sogod

echo +++ Clean-up database structure
tmpf=$(tempfile)
echo "DELETE FROM sogo_store;" > $tmpf
echo "DELETE FROM sogo_quick_appointment;" >> $tmpf
echo "DELETE FROM sogo_acl;" >> $tmpf
mysql -u root sogo < $tmpf
rm $tmpf

echo +++ Convert SoGo data format 
yes | /usr/share/doc/sogo/sql-update-3.0.0-to-combined-mysql.sh

echo +++ Start SoGo again
mv /etc/service/sogo/run.backup /etc/service/sogo/run
rm /tmp/sogo_stop

