
# syntax=docker/dockerfile:1

FROM rockylinux:8

# Suporting software versions
ARG IREDMAIL_VERSION=1.6.1
ARG GOSU_VERSION=1.14
ARG GLOBALADDRESSBOOK_VERSION=2.1
ARG COMPOSER_VERSION=2.4.1
ARG PHP_VERSION=8.0

# Default values changable at startup
ARG DOMAIN=DOMAIN
ARG HOSTNAME=HOSTNAME

### Installation
WORKDIR /opt/iredmail
ADD static_files/opt/iredmail /opt/iredmail

RUN mkdir -p /var/run/php-fpm/ \
    && chmod 755 /var/run/php-fpm \
    && touch /var/run/php-fpm/php-fpm.pid \
    && chown root:root /var/run/php-fpm/php-fpm.pid

# All-in-one installation
ADD static_files/opt/iredmail/packages /opt/iredmail/packages
RUN rpm -ivh packages/*.rpm \
    && dnf install -y mariadb-server mariadb-devel openssl procps dnf-utils unzip p7zip p7zip-plugins bzip2 arj lzop \
    && dnf install -y net-tools curl telnet python3-devel python3-requests python3-PyMySQL gcc which wget dialog \
    # Exclude GNUstep packages
    && sed -i '/^gpgcheck.*/a exclude=gnustep*' /etc/yum.repos.d/epel.repo \
    && dnf clean all \
    && dnf update -y \
    && mv packages/gosu-amd64-${GOSU_VERSION} /usr/bin/gosu \
    && chmod +x /usr/bin/gosu \
    && dnf module reset php -y \
    && dnf module enable php:remi-${PHP_VERSION} -y \
    && dnf module install php:remi-${PHP_VERSION} -y \
    && dnf module update php\* -y \
    && dnf install -y php php-fpm php-mysqlnd php-gd php-intl \
    && ln -s /usr/bin/python3 /usr/bin/python \
    && pip3 install uwsgi mysqlclient mysql-connector web.py \
    && dnf clean all \
    # Start temporary MariaDB server
    && mysql_install_db  --datadir=/var/lib/mysql --skip-name-resolve --force \
    && chown mysql:mysql /var/lib/mysql -R \
    && chown mysql:mysql /var/log/mariadb -R \
    && mysqld_safe & while ! mysqladmin ping --silent; do sleep 1; done \
    && echo "SELECT 1;"  | mysql \
            && ps -ef \
    # Unpack iRedMail
    && tar -xvzf packages/iRedMail-"${IREDMAIL_VERSION}".tar.gz --strip-components=1 \
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
    && dnf install -y supervisor python3-mysqlclient python3-webpy \
    && ln -s /opt/www/iredadmin/rc_scripts/uwsgi/rhel8.ini /opt/www/iredadmin/rc_scripts/uwsgi/rhel.ini \
    # Remove all dependencies and all caches
    && mkdir dumps \
    && for d in amavisd iredadmin iredapd roundcubemail sogo vmail mysql; do mysqldump $d | gzip -c > dumps/${d}.sql.gz; done \
    && yum clean all \
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

# Update Roundcubemail plugins
WORKDIR /opt/www/roundcubemail/plugins
RUN mkdir globaladdressbook | tar -xvzf /opt/iredmail/packages/roundcube-globaladdressbook-${GLOBALADDRESSBOOK_VERSION}.tar.gz --strip-components=1 -C globaladdressbook \
    && mkdir html5_notifier | tar -xvzf /opt/iredmail/packages/html5_notifier-0.6.4.tar.gz --strip-components=1 -C html5_notifier \
#    && mkdir microsoft-teams-notifier | tar -xvzf /opt/iredmail/packages/microsoft-teams-notifier-1.2.0.tar.gz --strip-components=1 -C microsoft-teams-notifier \
    && cd .. \
    && mv /opt/iredmail/packages/composer-${COMPOSER_VERSION}.phar ./composer.phar \
    && rm -f composer.lock \
    && php composer.phar update \
    && rm -fR /opt/iredmail/packages

# Enable Plugins
# Variables
ARG ROUNDCUBEMAIL_CONFIG_PATH=/opt/www/roundcubemail/config/config.inc.php
RUN sed -i "/plugins/c\$config['plugins'] = array('managesieve', 'password', 'zipdownload', 'globaladdressbook', 'html5_notifier');" ${ROUNDCUBEMAIL_CONFIG_PATH}

# Update Timezone for Date of Sender
RUN echo '/^(Date: .* [+-][0-9]{4})$/ REPLACE X-$1' >> /etc/postfix/header_checks

# Add Options to config
RUN sed -i "/] = LOG_MAIL;/a\$config['sql_debug'] = false;\n\$config['imap_debug'] = false;\n\$config['ldap_debug'] = false;\n\$config['smtp_debug'] = false;"  ${ROUNDCUBEMAIL_CONFIG_PATH}

# Starting mechanism
WORKDIR /opt/iredmail
ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord"]

# Open Ports:
# Apache: 80/tcp, 443/tcp Postfix: 25/tcp, 587/tcp
# Dovecot: 110/tcp, 143/tcp, 993/tcp, 995/tcp
EXPOSE 80 443 25 587 110 143 993 995

# Default values changable at startup
ENV SOGO_WORKERS=2
ENV TZ=Etc/UTC

