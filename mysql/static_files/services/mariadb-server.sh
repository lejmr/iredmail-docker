#!/bin/sh

export HOME="/root"
export USER="root"

# Remove default .my.cnf file
test /root/.my.cnf && rm /root/.my.cnf* -f

# Erase iRedMail certificates if do not exist
if [ ! -e /etc/pki/tls/certs/iRedMail.crt ]; then
    sed -i 's/ssl-/#ssl-/' /etc/my.cnf
fi

if [ ! -d /var/lib/mysql/mysql ]; then
    ### Create database filesystem if does not exist

    echo -n "*** Creating basic /var/lib/mysql filesystem.. "
    mysql_install_db  --datadir=/var/lib/mysql --skip-name-resolve --force
    chown mysql:mysql /var/lib/mysql -R
    echo "done."

    # Start temporary MariaDB instance
    mysqld_safe &
    while ! mysqladmin ping --silent; do sleep 1; done
    echo "SELECT 1;"  | mysql || exit 1

    ### At this moment MariaDB is running, and is open for everyone.. needs to be hardened
    # Update root password
    if [ ! -z ${MYSQL_ROOT_PASSWORD} ]; then
        echo "*** Configuring MySQL database.. "
        if [ "${MYSQL_ROOT_PASSWORD}" != "$CP" ]; then
            echo "(root password) "
            cat << EOF | mysql
    -- What's done in this file shouldn't be replicated
    -- or products like mysql-fabric won't work
    SET @@SESSION.SQL_LOG_BIN=0;
    DELETE FROM mysql.user WHERE user NOT IN ('mysql.sys', 'mysqlxsys', 'root', 'mysql') OR host NOT IN ('localhost') ;
    SET PASSWORD FOR 'root'@'localhost'=PASSWORD('${MYSQL_ROOT_PASSWORD}') ;
    GRANT ALL ON *.* TO 'root'@'localhost' WITH GRANT OPTION ;

    CREATE USER 'root'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}' ;
    GRANT ALL ON *.* TO 'root'@'%' WITH GRANT OPTION ;

    DROP DATABASE IF EXISTS test ;
    FLUSH PRIVILEGES ;
EOF
        fi

        cat << EOF > /root/.my.cnf
            [client]
            host=localhost
            user=root
            password="${MYSQL_ROOT_PASSWORD}"
EOF

    fi

    # Import initial structures
    DOMAIN=$(hostname -d)
    for dbname in amavisd iredadmin iredapd roundcubemail vmail sogo; do 
        i="/opt/iredmail/dumps/${dbname}.sql.gz"
        if [ "${dbname}" == "mysql" ]; then
            continue
        fi
        echo "Importing $i into $dbname"; 
        
        # Create database
        echo "CREATE DATABASE $dbname COLLATE utf8_general_ci;" | mysql

        # Import data
        zcat $i | sed -e "s/DOMAIN/${DOMAIN}/g" | mysql $dbname
    done

    # Create and grant technical accounts
    . /opt/iredmail/.cv
    cat << EOF | mysql
    -- TODO: set grant options properly
    SET @@SESSION.SQL_LOG_BIN=0;
    
    -- vmail
    CREATE USER 'vmail'@'localhost' IDENTIFIED BY '${VMAIL_DB_BIND_PASSWD}' ;
    GRANT ALL ON *.* TO 'vmail'@'localhost' WITH GRANT OPTION ;
    -- vmailadmin
    CREATE USER 'vmailadmin'@'localhost' IDENTIFIED BY '${VMAIL_DB_ADMIN_PASSWD}' ;
    GRANT ALL ON *.* TO 'vmailadmin'@'localhost' WITH GRANT OPTION ;
    -- amavisd
    CREATE USER 'amavisd'@'localhost' IDENTIFIED BY '${AMAVISD_DB_PASSWD}' ;
    GRANT ALL ON *.* TO 'amavisd'@'localhost' WITH GRANT OPTION ;
    -- iredadmin
    CREATE USER 'iredadmin'@'localhost' IDENTIFIED BY '${IREDADMIN_DB_PASSWD}' ;
    GRANT ALL ON *.* TO 'iredadmin'@'localhost' WITH GRANT OPTION ;
    -- roundcube
    CREATE USER 'roundcube'@'localhost' IDENTIFIED BY '${RCM_DB_PASSWD}' ;
    GRANT ALL ON *.* TO 'roundcube'@'localhost' WITH GRANT OPTION ;
    -- sogo
    CREATE USER 'sogo'@'localhost' IDENTIFIED BY '${SOGO_DB_PASSWD}' ;
    GRANT ALL ON *.* TO 'sogo'@'localhost' WITH GRANT OPTION ;
    -- iredapd
    CREATE USER 'iredapd'@'localhost' IDENTIFIED BY '${IREDAPD_DB_PASSWD}' ;
    GRANT ALL ON *.* TO 'iredapd'@'localhost' WITH GRANT OPTION ;    
    FLUSH PRIVILEGES ;
EOF

    # Update default email accounts
    if [ ! -z ${POSTMASTER_PASSWORD} ]; then
        echo "(postmaster password) "
        echo "UPDATE mailbox SET password='${POSTMASTER_PASSWORD}' WHERE username='postmaster@${DOMAIN}';" | mysql vmail
    fi

    # Stop temporary instance
    mysqladmin shutdown
else
    ### Update passwords for technical accounts
    echo "*** Updating password credentials"

    cat << EOF > /root/.my.cnf
            [client]
            host=localhost
            user=root
            password="${MYSQL_ROOT_PASSWORD}"
EOF

    # start temporary instance
    mysqld_safe &
    while ! mysqladmin ping --silent; do sleep 1; done
    echo "SELECT 1;"  | mysql || exit 1

    # Update credentials
    . /opt/iredmail/.cv
    cat << EOF | mysql 
    SET PASSWORD FOR 'vmail'@'localhost' = PASSWORD('$VMAIL_DB_BIND_PASSWD');
    SET PASSWORD FOR 'vmailadmin'@'localhost' = PASSWORD('$VMAIL_DB_ADMIN_PASSWD');
    SET PASSWORD FOR 'amavisd'@'localhost' = PASSWORD('$AMAVISD_DB_PASSWD');
    SET PASSWORD FOR 'iredadmin'@'localhost' = PASSWORD('$IREDADMIN_DB_PASSWD');
    SET PASSWORD FOR 'roundcube'@'localhost' = PASSWORD('$RCM_DB_PASSWD');
    SET PASSWORD FOR 'sogo'@'localhost' = PASSWORD('$SOGO_DB_PASSWD');
    SET PASSWORD FOR 'iredapd'@'localhost' = PASSWORD('$IREDAPD_DB_PASSWD');
    FLUSH PRIVILEGES;
EOF

    # stop temporary instance
    mysqladmin shutdown
fi

# Normal database server start
echo "*** Starting MySQL database.."
# exec mysqld_safe
exec /usr/libexec/mysqld --basedir=/usr --datadir=/var/lib/mysql --plugin-dir=/usr/lib64/mysql/plugin --user=mysql --log-error=/var/log/mariadb.log --open-files-limit=65535 --pid-file=/var/run/mariadb/mariadb.pid --port=3306
