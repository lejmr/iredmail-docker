#!/bin/bash
# The goal of this entrypoint is to generate passwords; subsequently, 
# start supervisord service which starts all necessary services.

if [ "$1" == "supervisord" ]; then
    echo "*** Starting SupervisorD"
    
    # Generate run time passwords
    if [ ! -e /opt/iredmail/.cv ]; then
        cat << EOF > /opt/iredmail/.cv
VMAIL_DB_BIND_PASSWD="$(openssl rand -hex 32)"
VMAIL_DB_ADMIN_PASSWD="$(openssl rand -hex 32)"
AMAVISD_DB_PASSWD="$(openssl rand -hex 32)"
IREDADMIN_DB_PASSWD="$(openssl rand -hex 32)"
RCM_DB_PASSWD="$(openssl rand -hex 32)"
SOGO_DB_PASSWD="$(openssl rand -hex 32)"
SOGO_SIEVE_MASTER_PASSWD="$(openssl rand -hex 32)"
IREDAPD_DB_PASSWD="$(openssl rand -hex 32)"
EOF
    fi

    # Generate SSL certificates if do not exist
    if [ ! -e /etc/ssl/private/iRedMail.key ] || [ ! -e /etc/ssl/certs/iRedMail.crt ]; then
        echo "Generating SSL cerificates"
        (cd /etc/ssl && . /opt/iredmail/tools/generate_ssl_keys.sh)
    fi

    # Start supervisord
    echo "Starting SupervisorD"
    exec supervisord -c /etc/supervisord.conf -u root
else
    # Start any other program
    exec $@
fi