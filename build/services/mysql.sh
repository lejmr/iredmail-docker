#!/bin/sh


if [ ! -d /var/lib/mysql/mysql ]; then
    echo "*** Creating database.."
    cd / && tar jxf /root/mysql.tar.bz2
    rm /root/mysql.tar.bz2
fi
    
exec /sbin/setuser mysql /usr/sbin/mysqld 
