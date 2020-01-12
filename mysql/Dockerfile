FROM centos:7
MAINTAINER Miloš Kozák <milos.kozak@lejmr.com>

# Suporting software versions
ARG IREDMAIL_VERSION=1.0

# Default values changable at startup
ARG DOMAIN=DOMAIN
ARG HOSTNAME=HOSTNAME

### Installation
WORKDIR /opt/iredmail
ADD static_files/opt/iredmail /opt/iredmail

# All-in-one installation
RUN yum install -y mariadb-server openssl \
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
    && yum install -y supervisor \
    # Remove all dependencies and all caches
    && mkdir dumps \
    && for d in amavisd iredadmin iredapd roundcubemail sogo vmail; do mysqldump $d | gzip -c > dumps/${d}.sql.gz; done \
    && yum clean all \
    && find /var/cache/yum/ -type f -exec rm -f {} \; \
    && rm /var/lib/mysql -rf \
    && rm -rf /var/lib/clamav/* \
    && rm -rf /var/vmail/vmail1/DOMAIN \
    && rm -f /etc/ssl/private/iRedMail.key \
    && rm -f /etc/ssl/certs/iRedMail.crt \
    && rm -f /var/lib/dkim/DOMAIN.pem \
    # Prepare for first run
    && tar jcf dumps/vmail.tar.bz2 /var/vmail \
    && rm -rf /var/vmail

# At this point the layer contains services configured by iRedMail installer
# However, some configurations need to be adapted, so the software composition
# works under docker. That is the main reason for closing this layer, and opening
# a new one in the next part of this Dockerfile

# Installation of all static files (some of them are conf file overrides)
ADD static_files /

ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord"]

# Adaptation of configuration files, for services can be started



# ### Final configuration
# RUN sed -i '/^Foreground /c Foreground true' /etc/clamav/clamd.conf \
#     && sed -i '/init.d/c pkill -sighup clamd' /etc/logrotate.d/clamav-daemon \
#     && sed -i '/^Foreground /c Foreground true' /etc/clamav/freshclam.conf \
#     && sed -i 's/^bind-address/#bind-address/' /etc/mysql/mysql.conf.d/mysqld.cnf \
#     && sed -i 's/SHOWWARNING[ \t]*=.*/SHOWWARNING=false/g' /etc/tmpreaper.conf \
#     && install -o amavis -g amavis -m 750 -d /var/lib/amavis/.spamassassin \
#     && install -o amavis -g amavis -m 640 -T /usr/share/spamassassin/user_prefs.template /var/lib/amavis/.spamassassin/user_prefs \
#     && rm -f /etc/ssl/private/iRedMail.key \
#     && rm -f /etc/ssl/certs/iRedMail.crt \
#     && rm -f /var/lib/dkim/DOMAIN.pem

# # Prepare for the first run
# RUN tar jcf /root/mysql.tar.bz2 /var/lib/mysql && rm -rf /var/lib/mysql \
#     && tar jcf /root/vmail.tar.bz2 /var/vmail && rm -rf /var/vmail \
#     && rm -rf /var/lib/clamav/*

# ADD update.sh /sbin/update-iredmail


# ### Startup services
# # Core Services
# ADD rc.local /etc/rc.local
# ADD services/mysql.sh /etc/service/mysql/run
# ADD services/postfix.sh /etc/service/postfix/run
# ADD services/amavis.sh /etc/service/amavis/run
# ADD services/iredapd.sh /etc/service/iredapd/run
# ADD services/dovecot.sh /etc/service/dovecot/run

# # Frontend
# ADD services/memcached.sh /etc/service/memcached/run
# ADD services/sogo.sh /etc/service/sogo/run
# ADD services/iredadmin.sh /etc/service/iredadmin/run
# ADD services/php7-fpm.sh /etc/service/php7-fpm/run
# ADD services/nginx.sh /etc/service/httpd/run

# # Enhancement
# ADD services/fail2ban.sh /etc/service/fail2ban/run
# ADD services/clamav-daemon.sh /etc/service/clamav-daemon/run
# ADD services/clamav-freshclam.sh /etc/service/clamav-freshclam/run
# ADD services/netdata.sh /etc/service/netdata/run
# ADD services/mlmmjadmin.sh /etc/service/mlmmjadmin/run


# ### Purge some packets and save disk space
# RUN apt-get purge -y -q dialog apt-utils augeas-tools \
#     && apt-get autoremove -y -q \
#     && apt-get clean -y -q \
#     && rm -rf /var/lib/apt/lists/*

# Open Ports:
# Apache: 80/tcp, 443/tcp Postfix: 25/tcp, 587/tcp
# Dovecot: 110/tcp, 143/tcp, 993/tcp, 995/tcp
EXPOSE 80 443 25 587 110 143 993 995

# Default values changable at startup
ENV SOGO_WORKERS=2
ENV TZ=Etc/UTC


# CMD ["/usr/bin/supervisord"]