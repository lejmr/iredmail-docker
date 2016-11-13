#!/bin/sh

### First wait until mysql starts
# service users are configured
while [ ! -f /var/tmp/mysql.run ]; do
  sleep 1
done
# MySQL actually runs
while ! mysqladmin ping -h localhost --silent; do
  sleep 1; 
done


# Service startup
if [ ! -z ${DOMAIN} ]; then 
    sed -i "s/DOMAIN/${DOMAIN}/g" /etc/postfix/main.cf /etc/postfix/aliases
    newaliases
fi

if [ ! -z ${HOSTNAME} ]; then 
    sed -i "s/HOSTNAME/${HOSTNAME}/g" /etc/postfix/main.cf
fi;


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

# Update MySQL password
. /opt/iredmail/.cv
sed -i "s/TEMP_VMAIL_DB_BIND_PASSWD/$VMAIL_DB_BIND_PASSWD/" /etc/postfix/mysql/catchall_maps.cf \
    /etc/postfix/mysql/domain_alias_maps.cf \
    /etc/postfix/mysql/recipient_bcc_maps_domain.cf \
    /etc/postfix/mysql/recipient_bcc_maps_user.cf \
    /etc/postfix/mysql/relay_domains.cf \
    /etc/postfix/mysql/sender_bcc_maps_domain.cf \
    /etc/postfix/mysql/sender_bcc_maps_user.cf \
    /etc/postfix/mysql/sender_dependent_relayhost_maps.cf \
    /etc/postfix/mysql/sender_login_maps.cf \
    /etc/postfix/mysql/transport_maps_domain.cf \
    /etc/postfix/mysql/transport_maps_user.cf \
    /etc/postfix/mysql/virtual_alias_maps.cf \
    /etc/postfix/mysql/virtual_mailbox_domains.cf \
    /etc/postfix/mysql/virtual_mailbox_maps.cf \
    /etc/postfix/mysql/domain_alias_catchall_maps.cf

postmap /etc/postfix/mysql/catchall_maps.cf \
    /etc/postfix/mysql/domain_alias_maps.cf \
    /etc/postfix/mysql/recipient_bcc_maps_domain.cf \
    /etc/postfix/mysql/recipient_bcc_maps_user.cf \
    /etc/postfix/mysql/relay_domains.cf \
    /etc/postfix/mysql/sender_bcc_maps_domain.cf \
    /etc/postfix/mysql/sender_bcc_maps_user.cf \
    /etc/postfix/mysql/sender_dependent_relayhost_maps.cf \
    /etc/postfix/mysql/sender_login_maps.cf \
    /etc/postfix/mysql/transport_maps_domain.cf \
    /etc/postfix/mysql/transport_maps_user.cf \
    /etc/postfix/mysql/virtual_alias_maps.cf \
    /etc/postfix/mysql/virtual_mailbox_domains.cf \
    /etc/postfix/mysql/virtual_mailbox_maps.cf \
    /etc/postfix/mysql/domain_alias_catchall_maps.cf

trap "trap_hup_signal" HUP
trap "trap_term_signal" TERM

echo "*** Starting postfix.."
touch /var/tmp/postfix.run
/usr/lib/postfix/sbin/master -c /etc/postfix -d &
pid=$!

# Loop "wait" until the postfix master exits
while wait $pid; test $? -gt 128
do
    kill -0 $pid 2> /dev/null || break;
done
