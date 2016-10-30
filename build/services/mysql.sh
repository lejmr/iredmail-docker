#!/bin/sh
    
if [ ! -d /var/lib/mysql/mysql ]; then
    echo -n "*** Creating database.. "
    cd / && tar jxf /root/mysql.tar.bz2
    rm /root/mysql.tar.bz2
    echo "done."
    
    if [ ! -z ${MYSQL_ROOT_PASSWORD} ]; then 
        echo -n "*** Configuring MySQL database.. "
        # Start MySQL 
        exec /sbin/setuser mysql /usr/sbin/mysqld &
        # TODO: better way for finding that process is running
        sleep 2
                
        # Update root password
        CP=$(awk '/password/{sub(/password=/, "", $0);print $0}' /root/.my.cnf)
        if [ "${MYSQL_ROOT_PASSWORD}" != "$CP" ]; then
            echo -n "(root password) "

            echo 'DELETE FROM mysql.user WHERE user LIKE "root";' > /tmp/root.sql
            echo "CREATE USER 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';" >>/tmp/root.sql
            echo "GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION ;" >> /tmp/root.sql
            echo "FLUSH PRIVILEGES ;" >> /tmp/root.sql
            mysql -u root -p$CP < /tmp/root.sql  > /dev/null 2>&1
            rm /tmp/root.sql
        
            # Update my.cnf for root
            echo "[client]\nuser=root\npassword=$MYSQL_ROOT_PASSWORD" > /root/.my.cnf
        fi; 
        
        # Update default email accounts
        if [ ! -z ${DOMAIN} ]; then 
            echo "(postmaster) "
            tmp=$(tempfile)
            mysqldump -u root -p${MYSQL_ROOT_PASSWORD} vmail mailbox alias domain domain_admins -r $tmp
            sed -i "s/DOMAIN/${DOMAIN}/g" $tmp
            mysql -u root -p${MYSQL_ROOT_PASSWORD} vmail < $tmp > /dev/null 2>&1
            rm $tmp
        fi
    
    
        # Stop this instance
        killall -s TERM mysqld
        echo "done."
    fi 
fi
    
echo "*** Starting MySQL database.."
exec /sbin/setuser mysql /usr/sbin/mysqld 
