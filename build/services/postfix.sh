#!/bin/sh

# Restore data in case of first run
if [ ! -d /var/vmail/backup ]; then
    echo "*** Creating vmail structure.."
    cd / && tar jxf /root/vmail.tar.bz2
    rm /root/vmail.tar.bz2
    
    if [ ! -z ${DOMAIN} ]; then 
        sed -i "s/DOMAIN/${DOMAIN}/g" /etc/postfix/main.cf /etc/postfix/aliases        
        mv /var/vmail/vmail1/DOMAIN /var/vmail/vmail1/$DOMAIN
    fi
    
    if [ ! -z ${HOSTNAME} ]; then 
        sed -i "s/HOSTNAME/${HOSTNAME}/g" /etc/postfix/main.cf
    fi;
    
    if [ ! -z ${HOSTNAME} ] && [ ! -z ${DOMAIN} ]; then 
        echo "127.0.0.1     ${HOSTNAME}.${DOMAIN}" >> /etc/hosts
    fi
    
    # Update of local aliases
    newaliases
fi

FILES="localtime services resolv.conf hosts"
for file in $FILES; do
    cp /etc/${file} /var/spool/postfix/etc/${file}
    chmod a+rX /var/spool/postfix/etc/${file}
done

trap_hup_signal() {
    echo "Reloading (from SIGHUP)"
    postfix reload
}

trap_term_signal() {
    echo "Stopping (from SIGTERM)"
    postfix stop
    exit 0
}

trap "trap_hup_signal" HUP
trap "trap_term_signal" TERM

/usr/lib/postfix/sbin/master -c /etc/postfix -d &
pid=$!

# Loop "wait" until the postfix master exits
while wait $pid; test $? -gt 128
do
    kill -0 $pid 2> /dev/null || break;
done
