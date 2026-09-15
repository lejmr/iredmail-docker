# syntax=docker/dockerfile:1
#
# Phase A image: iRedMail 1.8.8 (open source edition) unattended-installed
# on debian:13-slim, driven entirely at `docker build` time. See
# DEVELOPMENT.md for the overrides mechanism, the `admin` CLI contract, and
# how this differs from the legacy CentOS/Rocky Dockerfiles this was
# modelled on (mysql/Dockerfile, "Update to 1.6.1/Dockerfile").
FROM debian:13-slim

ARG IREDMAIL_VERSION=1.8.8
ARG TARGETARCH

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    LANG=C.UTF-8

WORKDIR /opt/iredmail

# --- Neutralise systemd for the duration of the build -----------------
# Debian package postinst scripts, and iRedMail's own service_control()
# (conf/core, iRedMail/functions/*.sh), call `systemctl` unconditionally
# on Debian (conf/global: `export USE_SYSTEMD='YES'` is hardcoded for the
# Linux branch - there is no env var to turn it off). There is no systemd
# running under `docker build`, so both policy-rc.d (stops packages
# auto-starting their daemon via /etc/init.d) and a no-op systemctl shim
# (stops both apt postinst and iRedMail.sh's own calls from failing the
# build) are installed before anything else.
RUN set -eux; \
    printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d; \
    chmod +x /usr/sbin/policy-rc.d; \
    mv /usr/bin/systemctl /usr/bin/systemctl.real 2>/dev/null || true; \
    printf '#!/bin/sh\n# ponytail: build-time no-op, real service control is supervisord at runtime\ncase "$1" in\n  is-active) exit 1 ;;\n  is-enabled) exit 1 ;;\n  *) exit 0 ;;\nesac\n' > /usr/bin/systemctl; \
    chmod +x /usr/bin/systemctl

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg2 sudo perl bzip2 dialog gettext-base \
        mariadb-server mariadb-client openssl procps net-tools; \
    curl -fsSL -o iRedMail.tar.gz \
        "https://github.com/iredmail/iRedMail/archive/refs/tags/${IREDMAIL_VERSION}.tar.gz"; \
    tar xzf iRedMail.tar.gz --strip-components=1; \
    rm iRedMail.tar.gz

# --- Unattended config file --------------------------------------------
# Real per-component passwords are randomly generated build secrets - they
# are only used to get the install to completion; MariaDB's data directory
# and the throw-away FIRST_DOMAIN are both thrown away at the end of this
# RUN (see the `rm -rf /var/lib/mysql` / `rm -rf /var/vmail` below), so
# these values never reach a running container. Real secrets are generated
# per-container at first start by scripts/first-start.sh.
COPY config/iredmail.conf.template /tmp/iredmail.conf.template
RUN set -eux; \
    export VMAIL_DB_BIND_PASSWD="$(openssl rand -hex 24)"; \
    export VMAIL_DB_ADMIN_PASSWD="$(openssl rand -hex 24)"; \
    export MLMMJADMIN_API_AUTH_TOKEN="$(openssl rand -hex 24)"; \
    export MYSQL_ROOT_PASSWD="$(openssl rand -hex 24)"; \
    export BUILD_DOMAIN="build.invalid"; \
    export BUILD_DOMAIN_ADMIN_PASSWD="$(openssl rand -hex 24)"; \
    export AMAVISD_DB_PASSWD="$(openssl rand -hex 24)"; \
    export IREDADMIN_DB_PASSWD="$(openssl rand -hex 24)"; \
    export SOGO_DB_PASSWD="$(openssl rand -hex 24)"; \
    export SOGO_SIEVE_MASTER_PASSWD="$(openssl rand -hex 24)"; \
    export IREDAPD_DB_PASSWD="$(openssl rand -hex 24)"; \
    envsubst < /tmp/iredmail.conf.template > /opt/iredmail/config; \
    chmod 0400 /opt/iredmail/config

# --- Unattended install --------------------------------------------------
# https://docs.iredmail.org/unattended.iredmail.installation.html
# AUTO_USE_EXISTING_CONFIG_FILE / AUTO_INSTALL_WITHOUT_CONFIRM skip dialog
# entirely and source ./config (dialog/config_via_dialog.sh, iRedMail.sh);
# a temporary MariaDB instance must be running for the installer's SQL
# schema import (functions/mysql.sh), same as the legacy mysql/Dockerfile.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -eux; \
    mkdir -p /var/lib/mysql /run/mysqld; \
    chown -R mysql:mysql /var/lib/mysql /run/mysqld; \
    mariadb-install-db --datadir=/var/lib/mysql --user=mysql --skip-name-resolve >/dev/null; \
    ( mysqld_safe --datadir=/var/lib/mysql --skip-networking=0 --bind-address=127.0.0.1 & ) ; \
    for i in $(seq 1 60); do mysqladmin ping --silent && break; sleep 1; done; \
    mysqladmin ping; \
    echo "127.0.0.1 mail.build.invalid mail localhost" >> /etc/hosts; \
    IREDMAIL_HOSTNAME=mail.build.invalid \
    AUTO_USE_EXISTING_CONFIG_FILE=y \
    AUTO_INSTALL_WITHOUT_CONFIRM=y \
    AUTO_CLEANUP_REMOVE_SENDMAIL=y \
    AUTO_CLEANUP_REMOVE_MOD_PYTHON=y \
    AUTO_CLEANUP_REPLACE_FIREWALL_RULES=n \
    AUTO_CLEANUP_RESTART_FIREWALL=n \
    AUTO_CLEANUP_REPLACE_MYSQL_CONFIG=y \
    AUTO_CLEANUP_RESTART_POSTFIX=n \
    bash iRedMail.sh; \
    mysqladmin shutdown || true; \
    # Replace the build-time passwords iRedMail just baked into every
    # component's config file with TEMP_* placeholder tokens, so
    # first-start.sh can substitute the *real*, per-container, randomly
    # generated runtime passwords in their place (the build-time MariaDB
    # data directory and every value derived from these passwords is
    # discarded a few RUN steps below - it never reaches a running
    # container). This is the modern equivalent of the TEMP_VMAIL_DB_*
    # convention in the legacy mysql/Dockerfile.
    for pair in \
        "$VMAIL_DB_BIND_PASSWD:TEMP_VMAIL_DB_BIND_PASSWD" \
        "$VMAIL_DB_ADMIN_PASSWD:TEMP_VMAIL_DB_ADMIN_PASSWD" \
        "$MYSQL_ROOT_PASSWD:TEMP_MYSQL_ROOT_PASSWD" \
        "$AMAVISD_DB_PASSWD:TEMP_AMAVISD_DB_PASSWD" \
        "$IREDADMIN_DB_PASSWD:TEMP_IREDADMIN_DB_PASSWD" \
        "$SOGO_DB_PASSWD:TEMP_SOGO_DB_PASSWD" \
        "$SOGO_SIEVE_MASTER_PASSWD:TEMP_SOGO_SIEVE_MASTER_PASSWD" \
        "$IREDAPD_DB_PASSWD:TEMP_IREDAPD_DB_PASSWD" \
        "$MLMMJADMIN_API_AUTH_TOKEN:TEMP_MLMMJADMIN_API_AUTH_TOKEN" \
    ; do \
        real="${pair%%:*}"; placeholder="${pair##*:}"; \
        grep -rlZ --include='*' -F "$real" /etc /opt 2>/dev/null \
            | xargs -0 -r sed -i "s#${real}#${placeholder}#g"; \
    done; \
    # Point the state iRedMail just wrote at the runtime volumes.
    # STORAGE_BASE_DIR was /var/vmail, MariaDB's datadir /var/lib/mysql;
    # both become symlinks so every config file iRedMail generated
    # (postfix, dovecot, mysql grants...) keeps working unmodified. Done in
    # this SAME layer as the temporary install, not a later RUN, so the
    # discarded MariaDB datadir and mail store never bloat an intermediate
    # image layer (row 15: image size).
    rm -rf /var/vmail; ln -s /data/vmail /var/vmail; \
    rm -rf /var/lib/mysql; ln -s /data/mysql /var/lib/mysql; \
    mkdir -p /data/mysql /data/vmail /data/certs /data/overrides; \
    mkdir -p /data/overrides/postfix/main.cf.d /data/overrides/dovecot; \
    echo '!include_try /data/overrides/dovecot/*.conf' >> /etc/dovecot/dovecot.conf; \
    rm -f /etc/ssl/private/iRedMail.key /etc/ssl/certs/iRedMail.crt; \
    rm -f /var/lib/dkim/*.pem /var/lib/dkim/*.private 2>/dev/null || true; \
    mv /usr/bin/systemctl.real /usr/bin/systemctl 2>/dev/null || true; \
    rm -f /usr/sbin/policy-rc.d

# --- Runtime dependencies (supervisord, no fail2ban / netdata) ---------
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -eux; \
    apt-get install -y --no-install-recommends supervisor; \
    apt-get purge -y --auto-remove fail2ban netdata || true

# Turn each systemd unit iRedMail's installer enabled into a supervisord
# program stanza - see build/gen-supervisord.sh for why (reuse the
# foreground invocation the unit already got right instead of re-deriving
# it by hand per package).
COPY build/gen-supervisord.sh /tmp/gen-supervisord.sh
RUN chmod +x /tmp/gen-supervisord.sh && /tmp/gen-supervisord.sh && rm /tmp/gen-supervisord.sh

# --- Assemble the SQL schema first-start.sh imports into a fresh datadir -
# vmail db tables (domain, mailbox, forwardings, admin, used_quota,
# last_login, share_folder...) already live in one consolidated file;
# amavisd needs its own db. No CREATE USER/GRANT here - first-start.sh
# creates every technical account with a freshly generated password
# (#57: least privilege per component), never a build-time one.
RUN set -eux; \
    mkdir -p /usr/local/lib/iredmail/sql; \
    { \
        echo "CREATE DATABASE IF NOT EXISTS vmail CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"; \
        echo "USE vmail;"; \
        cat /opt/iredmail/samples/iredmail/iredmail.mysql; \
        echo "CREATE DATABASE IF NOT EXISTS amavisd CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"; \
        echo "USE amavisd;"; \
        cat /opt/iredmail/samples/amavisd/amavisd.mysql; \
        echo "CREATE DATABASE IF NOT EXISTS sogo CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"; \
    } > /usr/local/lib/iredmail/sql/schema.sql; \
    rm -rf /opt/iredmail/samples /opt/iredmail/pkgs /opt/iredmail/.git /opt/iredmail/dumps

# --- Size cleanup --------------------------------------------------------
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -eux; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /root/.cache; \
    rm -rf /usr/share/doc /usr/share/man /usr/share/info; \
    find / -xdev -name '*.pyc' -delete 2>/dev/null || true

COPY scripts/ /usr/local/lib/iredmail/
COPY scripts/admin /usr/local/bin/admin
COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/admin /usr/local/bin/healthcheck.sh /entrypoint.sh \
    /usr/local/lib/iredmail/*.sh

VOLUME ["/data/mysql", "/data/vmail", "/data/certs", "/data/overrides"]

# 25 smtp, 465 smtps, 587 submission, 993 imaps, 443 https, 80 acme
EXPOSE 25 465 587 993 443 80

ENV CLAMAV=0

HEALTHCHECK --interval=10s --timeout=5s --start-period=60s --retries=12 \
    CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
