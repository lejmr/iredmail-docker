FROM phusion/baseimage:latest
MAINTAINER Miloš Kozák <milos.kozak@lejmr.com>

# Suporting software versions
ARG IREDMAIL_VERSION=0.9.7
ARG ADMINER_VERSION=4.3.1

# Default values changable at startup
ARG DOMAIN=DOMAIN
ARG HOSTNAME=HOSTNAME
ARG TIMEZONE=Europe/Prague
ARG SOGO_WORKERS=2

### Installation
# Prerequisites
ENV DEBIAN_FRONTEND noninteractive
RUN echo "APT::Install-Recommends 0;" >> /etc/apt/apt.conf.d/01-no-recommends \
    && echo "APT::Install-Suggests 0;" >> /etc/apt/apt.conf.d/01-no-recommends \
    && echo $TIMEZONE > /etc/timezone \
    && apt-get -q update \
    &&  apt-get upgrade -y \
    && apt-get install -y -q \
      apt-utils \
    && apt-get install -y -q \
      wget \
      bzip2 \
      iptables \
      openssl \
      mysql-server \ 
      netcat \
      memcached \
    && apt-get autoremove -y -q \
    && apt-get clean -y -q \ 
    && echo $DOMAIN > /etc/mailname \
    && echo $HOSTNAME > /opt/hostname \
    && mv /bin/uname /bin/uname_ \
    && mv /bin/hostname /bin/hostname_
    
COPY ./uname /bin/uname
COPY ./hostname /bin/hostname

# Install of iRedMail from sources
WORKDIR /opt/iredmail

RUN wget -O - https://bitbucket.org/zhb/iredmail/downloads/iRedMail-"${IREDMAIL_VERSION}".tar.bz2 | \
    tar xvj --strip-components=1

# Generate configuration file
COPY ./config-gen /opt/iredmail/config-gen
RUN sh ./config-gen $HOSTNAME $DOMAIN > ./config

# Initiate automatic installation process 
RUN sed s/$(hostname_)/$(cat /opt/hostname | xargs echo -n).$(cat /etc/mailname | xargs echo -n)/ /etc/hosts > /tmp/hosts_ \
    && cat /tmp/hosts_ > /etc/hosts \
    && rm /tmp/hosts_ \
    && echo $HOSTNAME > /etc/hostname \
    && sleep 5;service mysql start \
    && sed -i 's/1.3.0/1.3.3/' /opt/iredmail/pkgs/MD5.misc /opt/iredmail/conf/roundcube \
    && sed -i 's/9f81625029663c7b19402542356abd5e/71b16babe3beb7639ad7a4595b3ac92a/' /opt/iredmail/pkgs/MD5.misc \
    && IREDMAIL_DEBUG='NO' \
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
    && apt-get autoremove -y -q \
    && apt-get clean -y -q  

### Final configuration
RUN . ./config \
    && sed -i 's/PREFORK=.*$'/PREFORK=$SOGO_WORKERS/ /etc/default/sogo \
    && sed -i 's/WOWorkersCount.*$'/WOWorkersCount=$SOGO_WORKERS\;/ /etc/sogo/sogo.conf \
    && sed -i '/^Foreground /c Foreground true' /etc/clamav/clamd.conf \
    && sed -i '/init.d/c pkill -sighup clamd' /etc/logrotate.d/clamav-daemon \
    && sed -i '/^Foreground /c Foreground true' /etc/clamav/freshclam.conf \
    && sed -i 's/^bind-address/#bind-address/' /etc/mysql/mysql.conf.d/mysqld.cnf

# Prepare for the first run
RUN tar jcf /root/mysql.tar.bz2 /var/lib/mysql && rm -rf /var/lib/mysql \
    && tar jcf /root/vmail.tar.bz2 /var/vmail && rm -rf /var/vmail \
    && tar jcf /root/clamav.tar.bz2 /var/lib/clamav && rm -rf /var/lib/clamav

# Install Adminer
RUN wget https://www.adminer.org/static/download/${ADMINER_VERSION}/adminer-${ADMINER_VERSION}.php -O /opt/www/roundcubemail/adminer.php
ADD update.sh /sbin/update-iredmail


### Startup services
# Core Services
ADD rc.local /etc/rc.local
ADD services/mysql.sh /etc/service/mysql/run
ADD services/postfix.sh /etc/service/postfix/run
ADD services/amavis.sh /etc/service/amavis/run
ADD services/iredapd.sh /etc/service/iredapd/run
ADD services/dovecot.sh /etc/service/dovecot/run

# Frontend
ADD services/memcached.sh /etc/service/memcached/run
ADD services/sogo.sh /etc/service/sogo/run
ADD services/iredadmin.sh /etc/service/iredadmin/run
ADD services/php7-fpm.sh /etc/service/php7-fpm/run
ADD services/nginx.sh /etc/service/httpd/run

# Enhancement
ADD services/fail2ban.sh /etc/service/fail2ban/run
ADD services/clamav-daemon.sh /etc/service/clamav-daemon/run
ADD services/clamav-freshclam.sh /etc/service/clamav-freshclam/run


### Purge some packets and save disk space
RUN apt-get purge -y -q dialog apt-utils augeas-tools \
    && apt-get autoremove -y -q \
    && apt-get clean -y -q \
    && rm -rf /var/lib/apt/lists/*

# Open Ports:
# Apache: 80/tcp, 443/tcp Postfix: 25/tcp, 587/tcp
# Dovecot: 110/tcp, 143/tcp, 993/tcp, 995/tcp
EXPOSE 80 443 25 587 110 143 993 995
