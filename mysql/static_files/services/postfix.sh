#!/bin/sh

### First wait until mysql starts
DOMAIN=$(hostname -d)
HOSTNAME=$(hostname -s)

# Service startup
sed -i "s/HOSTNAME/${HOSTNAME}/g" /etc/postfix/main.cf
sed -i "s/DOMAIN/${DOMAIN}/g" /etc/postfix/main.cf /etc/postfix/aliases
newaliases


# Restore data in case of first run
if [ ! -d /var/vmail/backup ] && [ ! -d /var/vmail/vmail1/${DOMAIN} ]; then
    echo "*** Creating vmail structure.."
    cd / && tar jxf /opt/iredmail/dumps/vmail.tar.bz2
    mv /var/vmail/vmail1/DOMAIN /var/vmail/vmail1/${DOMAIN}
    rm /opt/iredmail/dumps/vmail.tar.bz2

    # Patch iredmail-tips and welcome email
    . /opt/iredmail/.cv
    MAILDIR="/var/vmail/vmail1/${DOMAIN}/p/o/s/postmaster/Maildir/new"
    FILES="/opt/iredmail/iRedMail.tips ${MAILDIR}/details.eml"
    sed -i "s/Root user:[ \t]*root,[ \t]*Password:[ \t]*.*/Root user: root, Password:\"${MYSQL_ROOT_PASSWORD}\"/" ${FILES}
    sed -i "s/Username:[ \t]*vmail,[ \t]*Password:[ \t]*.*/Username: vmail, Password:\"${VMAIL_DB_BIND_PASSWD}\"/" ${FILES}
    sed -i "s/Username:[ \t]*vmailadmin,[ \t]*Password:[ \t]*.*/Username: vmailadmin, Password:\"${VMAIL_DB_ADMIN_PASSWD}\"/" ${FILES}
    sed -i "/Database user:[ \t]*amavisd/{n;s/Database password:[ \t]*.*/Database password: \"${AMAVISD_DB_PASSWD}\"/}" ${FILES}
    sed -i "/Username:[ \t]*iredapd/{n;s/Password:[ \t]*.*/Password: \"${IREDAPD_DB_PASSWD}\"/}" ${FILES}
    sed -i "/URL:[ \t]*https:.*\/iredadmin\//{n;n;s/Password:[ \t]*.*/Password: \"${POSTMASTER_PASSWORD}\"/}" ${FILES}
    sed -i "/Username:[ \t]iredadmin/{n;s/Password:[ \t]*.*/Password: \"${IREDADMIN_DB_PASSWD}\"/}" ${FILES}
    sed -i "/URL:[ \t]*https:.*\/mail\//{n;n;s/Password:[ \t]*.*/Password: \"${POSTMASTER_PASSWORD}\"/}" ${FILES}
    sed -i "/Username:[ \t]roundcube/{n;s/Password:[ \t]*.*/Password: \"${RCM_DB_PASSWD}\"/}" ${FILES}
    sed -i "/Database user:[ \t]*sogo/{n;s/Database password:[ \t]*.*/Database password: \"${SOGO_DB_PASSWD}\"/}" ${FILES}
    sed -i "/username:[ \t]*sogo_sieve_master@not-exist\.com/{n;s/password:[ \t]*.*/password: \"${SOGO_SIEVE_MASTER_PASSWD}\"/}" ${FILES}
    # TODO: needs to be resolved after amavis is implemented
    # for file in $FILES; do
        # /bin/echo -e "$(sed '/DNS record for DKIM support:/q' ${file})\n$(amavisd-new showkeys)\n\n$(sed -ne '/Amavisd-new:/,$ p' ${file})" > ${file}
    # done
    FILES="${FILES} ${MAILDIR}/links.eml ${MAILDIR}/mua.eml ${MAILDIR}/details.eml"
    sed -i "s/DOMAIN/${DOMAIN}/g" ${FILES}
    sed -i "s/HOSTNAME/${HOSTNAME}/g" ${FILES}
fi

FILES="resolv.conf hosts"
for file in $FILES; do
    cat /etc/${file} > /var/spool/postfix/etc/${file}
    # chmod a+rX /var/spool/postfix/etc/${file}
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

trap_term_kill() {
    echo "Stopping (from SIGKILL)"
    kill -9 $(cat /var/spool/postfix/pid/master.pid)
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
    /etc/postfix/mysql/transport_maps_maillist.cf \
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
trap "trap_term_signal" TERM EXIT
trap "trap_term_kill" KILL

echo "*** Starting postfix.."
touch /var/tmp/postfix.run
# chown -R postfix /var/spool/postfix
postfix start

while [ "$(pidof master)" != "" ] ;
do
    sleep 1
done

# I dont like postfix is started like this because postfix get PID 1 as parent
# Even though its parent should be supervisord.
# root       744     1  0 12:56 pts/0    00:00:00 /bin/sh /services/postfix.sh
# root       834     1  0 12:56 ?        00:00:00 /usr/libexec/postfix/master -w
# postfix    835   834  0 12:56 ?        00:00:00 pickup -l -t unix -u
# postfix    836   834  0 12:56 ?        00:00:00 qmgr -l -t unix -u
# postfix    839   834  0 12:56 ?        00:00:00 proxymap -t unix -u