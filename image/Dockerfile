# syntax=docker/dockerfile:1
#
# Phase A image: iRedMail 1.8.8 (open source edition) unattended-installed
# on debian:13-slim, driven entirely at `docker build` time. See
# DEVELOPMENT.md for the overrides mechanism, the `admin` CLI contract, and
# how this differs from the legacy CentOS/Rocky Dockerfiles this was
# modelled on (mysql/Dockerfile, "Update to 1.6.1/Dockerfile").
FROM debian:13-slim

ARG IREDMAIL_VERSION=1.8.8
# sha256 of the archive/refs/tags/${IREDMAIL_VERSION}.tar.gz below - a git
# tag is mutable (force-push/retag), unlike a checksum; bump both together
# on a version bump (`curl -fsSL <url> | sha256sum`).
ARG IREDMAIL_SHA256=3754794897d18ecdf2d277fa25682c048d479016a56b41bc979ab756a786de6e
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
    echo "${IREDMAIL_SHA256}  iRedMail.tar.gz" | sha256sum -c -; \
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
    # convention in the legacy mysql/Dockerfile. The *_PASSWD vars were
    # exported in the earlier RUN that wrote ./config (a separate shell,
    # separate layer) - source that file here to get them back.
    . /opt/iredmail/config; \
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
        grep -rlZ --include='*' --exclude='*.db' -F "$real" /etc /opt 2>/dev/null \
            | xargs -0 -r sed -i "s#${real}#${placeholder}#g"; \
    done; \
    postalias /etc/postfix/aliases; newaliases; \
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

# --- Row 16: nothing listens except 25/465/587/993/443(+80) -----------
# iRedMail's own defaults already bind most internal daemons to
# LOCAL_ADDRESS (127.0.0.1: amavis, SOGo, memcached - iRedMail/conf/*), but
# MariaDB, Dovecot's non-mail-client services (managesieve, doveadm,
# old-stats) and iRedAPD's policy socket are not scoped down by the
# installer. Force loopback-only explicitly rather than trust the default,
# and re-open only the one Dovecot listener row 16 actually allows public:
# imaps (993). Plaintext imap (143) is NOT in row 16's list, so it is
# pinned loopback-only explicitly below - iRedMail's own dovecot.conf
# template already has its own `listen = *` line further down (Dovecot 2.4:
# last scalar assignment in the file wins), which silently overrode an
# earlier `sed '1a ...'` global default and left 143 open to the world
# (found by an nmap scan from a sibling container: `143/tcp open imap`).
RUN set -eux; \
    sed -i "s/^bind-address.*/bind-address = 127.0.0.1/" /etc/mysql/mariadb.conf.d/50-server.cnf \
        || echo 'bind-address = 127.0.0.1' >> /etc/mysql/mariadb.conf.d/50-server.cnf; \
    sed -i '1a listen = 127.0.0.1' /etc/dovecot/dovecot.conf; \
    printf '\nservice imap-login {\n  inet_listener imap {\n    listen = 127.0.0.1\n  }\n  inet_listener imaps {\n    listen = *\n  }\n}\n' \
        >> /etc/dovecot/dovecot.conf; \
    printf '\nservice pop3-login {\n  inet_listener pop3 {\n    listen = 127.0.0.1\n  }\n  inet_listener pop3s {\n    listen = 127.0.0.1\n  }\n}\nservice managesieve-login {\n  inet_listener sieve {\n    listen = 127.0.0.1\n  }\n}\n' \
        >> /etc/dovecot/dovecot.conf; \
    doveconf -n >/dev/null; \
    grep -q '^\$inet_socket_bind' /etc/amavis/conf.d/50-user 2>/dev/null || \
        echo '$inet_socket_bind = "127.0.0.1";' >> /etc/amavis/conf.d/50-user; \
    grep -rl "^bind_host" /opt/iredapd/settings.py 2>/dev/null | xargs -r sed -i "s/^bind_host.*/bind_host = '127.0.0.1'/" || true; \
    # This build host (Colima/Rosetta) has no IPv6 - '::'/'::1' listeners
    # made dovecot fail to start ("Fatal: Failed to start listeners").
    # IPv4-only is also all row 16 needs.
    :

# --- Row 8: unauthenticated relay is a hard 5xx, not a 4xx defer --------
# Postfix >=3.6's built-in smtpd_relay_restrictions default (active here:
# compatibility_level=3.6) is "permit_mynetworks, permit_sasl_authenticated,
# defer_unauth_destination" - a *temporary* 454 4.7.1, on the theory that a
# later restriction class might still accept the mail. relay_restrictions
# runs before recipient_restrictions in the RCPT check order, so its 4xx
# fires before smtpd_recipient_restrictions' own reject_unauth_destination
# (5xx) is ever reached - an unauthenticated relay attempt got a soft defer
# instead of the acceptance suite's `554 5.7.1 ... Relay access denied`
# (row 8). Pin it to the pre-3.6 hard-reject behaviour explicitly.
RUN postconf -e "smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination"

# --- Row 5: quota is checked, not just configured -----------------------
# iRedMail's own generated main.cf puts Dovecot's quota-status policy
# service (127.0.0.1:12340, whose quota_status_overquota literally IS
# row 5's expected "552 5.2.2 Mailbox is full") in
# smtpd_recipient_restrictions, AFTER permit_sasl_authenticated - which
# unconditionally PERMITs the recipient for every authenticated submission
# (the normal user flow) before that check is ever reached, and even when
# reached, no message body exists yet at RCPT time to measure against the
# quota. Confirmed by sending a 2MB message as a 1MB-quota user over
# authenticated submission (587): postfix accepted it and dovecot
# delivered it in full, no 552, no bounce - i.e. quota was silently not
# enforced despite being "wired". Move the same check to
# smtpd_end_of_data_restrictions (size is known there, and that list has
# no earlier permit_sasl_authenticated to bypass it).
RUN postconf -e "smtpd_end_of_data_restrictions = check_policy_service inet:127.0.0.1:7777, check_policy_service inet:127.0.0.1:12340"

# --- Remove iRedMail's own wildcard DKIM key from amavisd.conf ----------
# The installer wrote a `dkim_key('build.invalid', ...)` line plus a
# catch-all `@dkim_signature_options_bysender_maps` ('.' => ...) into
# conf.d/50-user for the throw-away build-time domain. `admin domain add`
# (image/scripts/common.sh: regenerate_amavis_dkim_include) fully
# regenerates a *separate* conf.d file with one dkim_key per real domain
# (#50/#92 - no wildcard key) - so the installer's own lines must be
# removed here, or amavis fails to start ("dkim_key: selector dkim for
# domain X already in use") the first time a real domain reuses that
# rewritten placeholder text (first-start.sh's hostname/domain rewiring
# turns 'build.invalid' into the real domain in every file, this one
# included).
RUN sed -i \
    -e "/^dkim_key('build.invalid'/d" \
    -e '/^@dkim_signature_options_bysender_maps = ({$/,/^});$/d' \
    /etc/amavis/conf.d/50-user

# --- Runtime dependencies (supervisord, no fail2ban / netdata) ---------
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -eux; \
    apt-get update; \
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

# No VOLUME instruction here (deliberately - row 13/#84): Docker
# auto-provisions an anonymous volume for any VOLUME-declared path a
# runner doesn't explicitly mount, which makes `mountpoint -q` in
# require_mountpoints() (common.sh) true for a forgotten /data/mysql too -
# the exact silent-anonymous-datadir failure #84 exists to catch. Verified
# by running the image with only some of /data/* bind-mounted: with
# VOLUME declared, mariadb wrote into an anonymous volume and crash-looped
# forever (permission-denied on ./ddl_recovery.log, wrong ownership) with
# no FATAL message; without it, the missing mount is just a plain
# writable-layer directory and require_mountpoints() correctly refuses to
# start. compose.yaml (repo root and test/) already declares the real
# named volumes for these paths - nothing needs Docker's anonymous-volume
# fallback.

# 25 smtp, 465 smtps, 587 submission, 993 imaps, 443 https, 80 acme
EXPOSE 25 465 587 993 443 80

ENV CLAMAV=0

HEALTHCHECK --interval=10s --timeout=5s --start-period=60s --retries=12 \
    CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
