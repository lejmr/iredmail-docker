#!/bin/sh
    
if [ ! -d /var/lib/mysql/mysql ]; then
    echo -n "*** Creating database.. "
    cd / && tar jxf /root/mysql.tar.bz2
    rm /root/mysql.tar.bz2
    echo "done."
fi

# Start database for changes
exec /sbin/setuser mysql /usr/sbin/mysqld --skip-grant-tables &
echo "Waiting for MySQL is up"
while ! mysqladmin ping -h localhost --silent; do
    echo -n "."
  sleep 1; 
done
echo

# Update root password
if [ ! -z ${MYSQL_ROOT_PASSWORD} ]; then 
    echo -n "*** Configuring MySQL database.. "
    # Start MySQL 
    
    if [ "${MYSQL_ROOT_PASSWORD}" != "$CP" ]; then
        echo -n "(root password) "

        echo 'DELETE FROM mysql.user WHERE user LIKE "root";' > /tmp/root.sql
        echo "FLUSH PRIVILEGES;" >> /tmp/root.sql
        echo "CREATE USER 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';" >>/tmp/root.sql
        echo "GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION ;" >> /tmp/root.sql
        echo "FLUSH PRIVILEGES;" >> /tmp/root.sql
        mysql -u root < /tmp/root.sql > /dev/null 2>&1
        rm /tmp/root.sql
    
        # Update my.cnf for root
        echo "[client]\nuser=root\npassword=$MYSQL_ROOT_PASSWORD" > /root/.my.cnf
    fi; 
fi 


# Update default email accounts
if [ ! -z ${DOMAIN} ]; then 
    echo "(postmaster) "
    tmp=$(tempfile)
    mysqldump -u root -p${MYSQL_ROOT_PASSWORD} vmail mailbox alias domain domain_admins -r $tmp
    sed -i "s/DOMAIN/${DOMAIN}/g" $tmp
    
    # Update default email accounts
    if [ ! -z ${POSTMASTER_PASSWORD} ]; then 
        echo "(postmaster password) "
        echo "UPDATE mailbox SET password='${POSTMASTER_PASSWORD}' WHERE username='postmaster@${DOMAIN}';" >> $tmp
    fi
    
    mysql -u root -p${MYSQL_ROOT_PASSWORD} vmail < $tmp > /dev/null 2>&1
    rm $tmp
fi


# Update passwords for service accounts
. /opt/iredmail/.cv
tmp=$(tempfile)
echo "DELETE FROM user WHERE Host='hostname.domain';" >> $tmp
echo "SET PASSWORD FOR 'vmail'@'localhost' = PASSWORD('$VMAIL_DB_BIND_PASSWD');" >> $tmp
echo "SET PASSWORD FOR 'vmailadmin'@'localhost' = PASSWORD('$VMAIL_DB_ADMIN_PASSWD');" >> $tmp
echo "SET PASSWORD FOR 'amavisd'@'localhost' = PASSWORD('$AMAVISD_DB_PASSWD');" >> $tmp
echo "SET PASSWORD FOR 'iredadmin'@'localhost' = PASSWORD('$IREDADMIN_DB_PASSWD');" >> $tmp
echo "SET PASSWORD FOR 'roundcube'@'localhost' = PASSWORD('$RCM_DB_PASSWD');" >> $tmp
echo "SET PASSWORD FOR 'sogo'@'localhost' = PASSWORD('$SOGO_DB_PASSWD');" >> $tmp
#echo "SET PASSWORD FOR 'vmail'@'localhost' = PASSWORD('$SOGO_SIEVE_MASTER_PASSWD');" >> $tmp
echo "SET PASSWORD FOR 'iredapd'@'localhost' = PASSWORD('$IREDAPD_DB_PASSWD');" >> $tmp
echo "FLUSH PRIVILEGES;" >> $tmp
echo "(service accounts) "
mysql -u root -p${MYSQL_ROOT_PASSWORD} mysql < $tmp > /dev/null 2>&1


# Stop temporary MySQL
killall -s TERM mysqld
rm $tmp
echo "done."

    
echo "*** Starting MySQL database.."
touch /var/tmp/mysql.run
exec /sbin/setuser mysql /usr/sbin/mysqld