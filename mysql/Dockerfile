FROM centos:7
MAINTAINER Miloš Kozák <milos.kozak@lejmr.com>

# Suporting software versions
ARG IREDMAIL_VERSION=1.3.1
ARG GOSU_VERSION=1.12

# Default values changable at startup
ARG DOMAIN=DOMAIN
ARG HOSTNAME=HOSTNAME

### Installation
WORKDIR /opt/iredmail
ADD static_files/opt/iredmail /opt/iredmail

# All-in-one installation
RUN yum install -y mariadb-server openssl \
    && curl -o /usr/bin/gosu -SL "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-amd64" \
    && chmod +x /usr/bin/gosu \
    # Start temporary MariaDB server
    && mysql_install_db  --datadir=/var/lib/mysql --skip-name-resolve --force \
    && chown mysql:mysql /var/lib/mysql -R \
    && mysqld_safe & while ! mysqladmin ping --silent; do sleep 1; done \
    && echo "SELECT 1;"  | mysql \
    && ps -ef \
    # Download iRedMail
    && curl -k -q https://codeload.github.com/iredmail/iRedMail/tar.gz/"${IREDMAIL_VERSION}" | \
    tar xvz --strip-components=1 \
    # Prepare default configuration and install
    && static/config-gen HOSTNAME DOMAIN > ./config \
    && IREDMAIL_DEBUG='NO' \
       IREDMAIL_HOSTNAME="HOSTNAME.DOMAIN" \
       CHECK_NEW_IREDMAIL='NO' \
       AUTO_USE_EXISTING_CONFIG_FILE=y \
       AUTO_INSTALL_WITHOUT_CONFIRM=y \
       AUTO_CLEANUP_REMOVE_SENDMAIL=y \
       AUTO_CLEANUP_REMOVE_MOD_PYTHON=y \
       AUTO_CLEANUP_REPLACE_FIREWALL_RULES=n \
       AUTO_CLEANUP_RESTART_IPTABLES=n \
       AUTO_CLEANUP_REPLACE_MYSQL_CONFIG=y \
       AUTO_CLEANUP_RESTART_POSTFIX=n \
       bash iRedMail.sh \
    && yum install -y supervisor MySQL-python python-webpy \
    # Remove all dependencies and all caches
    && mkdir dumps \
    && for d in amavisd iredadmin iredapd roundcubemail sogo vmail mysql; do mysqldump $d | gzip -c > dumps/${d}.sql.gz; done \
    && yum clean all \
    && find /var/cache/yum/ -type f -exec rm -f {} \; \
    && rm /var/lib/mysql -rf \
    && rm -rf /var/lib/clamav/* \
    && tar jcf dumps/vmail.tar.bz2 /var/vmail \
    && rm -rf /var/vmail/vmail1/DOMAIN \
    && rm -f /etc/ssl/private/iRedMail.key \
    && rm -f /etc/ssl/certs/iRedMail.crt \
    && rm -f /var/lib/dkim/DOMAIN.pem \
    # Prepare for first run
    && rm -rf /var/vmail

# At this point the layer contains services configured by iRedMail installer
# However, some configurations need to be adapted, so the software composition
# works under docker. That is the main reason for closing this layer, and opening
# a new one in the next part of this Dockerfile

# Installation of all static files (some of them are conf file overrides)
ADD static_files /

# Starting mechanism
ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord"]

# Open Ports:
# Apache: 80/tcp, 443/tcp Postfix: 25/tcp, 587/tcp
# Dovecot: 110/tcp, 143/tcp, 993/tcp, 995/tcp
EXPOSE 80 443 25 587 110 143 993 995

# Default values changable at startup
ENV SOGO_WORKERS=2
ENV TZ=Etc/UTC
