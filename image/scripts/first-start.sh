#!/bin/bash
# Runs once, the very first time a container boots against an empty
# /data/mysql (marker: /data/secrets/.initialized) - the truly one-time
# steps: MariaDB datadir init, schema import, technical-account creation,
# the initial domain + postmaster mailbox. Everything here must be
# idempotent-safe to re-source-but-not-re-run: entrypoint.sh only calls it
# when the marker is missing.
#
# Rendering /etc and /opt config files with these secrets (and the
# hostname/domain) is NOT here - that must run on every start, not just
# this one, because those directories are not volumes: see
# render-config.sh, which entrypoint.sh always calls after this.
set -euo pipefail
. /usr/local/lib/iredmail/common.sh

MAIL_DOMAIN="${MAIL_DOMAIN:?MAIL_DOMAIN env var is required on first start}"
HOSTNAME_FQDN="${HOSTNAME_FQDN:-mail.${MAIL_DOMAIN}}"

echo "*** first start: initialising MariaDB datadir"
mkdir -p /data/mysql /run/mysqld
chown -R mysql:mysql /data/mysql /run/mysqld
mariadb-install-db --datadir=/data/mysql --user=mysql --skip-name-resolve >/dev/null

# A fresh named volume mounts as root:root 0755 - dovecot's LDA/IMAP run as
# vmail:vmail (STORAGE_BASE_DIR=/var/vmail -> /data/vmail) and need to
# create the per-domain/per-user Maildir tree under it themselves, or every
# delivery fails ("mkdir ... Permission denied", row 4/6).
chown vmail:vmail /data/vmail

mysqld_safe --datadir=/data/mysql --skip-networking=0 --bind-address=127.0.0.1 &
for i in $(seq 1 60); do mysqladmin ping --silent 2>/dev/null && break; sleep 1; done
mysqladmin ping

MYSQL_ROOT_PW="$(secret mysql_root.pw)"
mysql -uroot <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PW}';
FLUSH PRIVILEGES;
SQL

echo "*** first start: importing schemas"
mysql -uroot -p"${MYSQL_ROOT_PW}" < /usr/local/lib/iredmail/sql/schema.sql

VMAIL_DB_BIND_PW="$(secret vmail_bind.pw)"
VMAIL_DB_ADMIN_PW="$(secret vmail_admin.pw)"
AMAVISD_DB_PW="$(secret amavisd.pw)"
IREDADMIN_DB_PW="$(secret iredadmin.pw)"
SOGO_DB_PW="$(secret sogo.pw)"
IREDAPD_DB_PW="$(secret iredapd.pw)"
ADMIN_CLI_PW="$(secret mysql_admin_cli.pw)"

mysql -uroot -p"${MYSQL_ROOT_PW}" <<SQL
CREATE USER IF NOT EXISTS 'vmail'@'127.0.0.1' IDENTIFIED BY '${VMAIL_DB_BIND_PW}';
GRANT SELECT ON vmail.* TO 'vmail'@'127.0.0.1';
CREATE USER IF NOT EXISTS 'vmailadmin'@'127.0.0.1' IDENTIFIED BY '${VMAIL_DB_ADMIN_PW}';
GRANT SELECT,INSERT,DELETE,UPDATE ON vmail.* TO 'vmailadmin'@'127.0.0.1';
CREATE USER IF NOT EXISTS 'amavisd'@'127.0.0.1' IDENTIFIED BY '${AMAVISD_DB_PW}';
GRANT ALL PRIVILEGES ON amavisd.* TO 'amavisd'@'127.0.0.1';
CREATE USER IF NOT EXISTS 'iredadmin'@'127.0.0.1' IDENTIFIED BY '${IREDADMIN_DB_PW}';
GRANT SELECT,INSERT,DELETE,UPDATE ON vmail.* TO 'iredadmin'@'127.0.0.1';
-- iRedAdmin's own db (sessions/log/settings - SQL/iredadmin.mysql, now part
-- of schema.sql): without this grant every page 500s on the session table.
GRANT SELECT,INSERT,DELETE,UPDATE ON iredadmin.* TO 'iredadmin'@'127.0.0.1';
CREATE USER IF NOT EXISTS 'sogo'@'127.0.0.1' IDENTIFIED BY '${SOGO_DB_PW}';
GRANT ALL PRIVILEGES ON sogo.* TO 'sogo'@'127.0.0.1';
GRANT SELECT ON vmail.* TO 'sogo'@'127.0.0.1';
CREATE USER IF NOT EXISTS 'iredapd'@'127.0.0.1' IDENTIFIED BY '${IREDAPD_DB_PW}';
GRANT SELECT ON vmail.* TO 'iredapd'@'127.0.0.1';
-- iRedAPD's own db (throttle/greylisting/... - SQL/iredapd.mysql, now
-- part of schema.sql): without this grant every policy check logs a SQL
-- access-denied error on its own db.
GRANT SELECT,INSERT,DELETE,UPDATE ON iredapd.* TO 'iredapd'@'127.0.0.1';
-- least-privilege technical account for the admin CLI (#57): only vmail db.
CREATE USER IF NOT EXISTS 'admin_cli'@'127.0.0.1' IDENTIFIED BY '${ADMIN_CLI_PW}';
GRANT SELECT,INSERT,DELETE,UPDATE ON vmail.* TO 'admin_cli'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

echo "$HOSTNAME_FQDN" > "${SECRETS_DIR}/hostname"
echo "$MAIL_DOMAIN" > "${SECRETS_DIR}/mail_domain"

echo "*** first start: TLS certificate (self-signed, CN=${HOSTNAME_FQDN}) unless mounted"
if [ ! -s /data/certs/cert.pem ] || [ ! -s /data/certs/key.pem ]; then
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
        -subj "/CN=${HOSTNAME_FQDN}" \
        -keyout /data/certs/key.pem -out /data/certs/cert.pem >/dev/null 2>&1
    chmod 0600 /data/certs/key.pem
fi

# Config files (/etc, /opt) still carry the build-time TEMP_*/build.invalid
# placeholders at this point - first-start.sh only ever creates the
# technical MySQL accounts (above) and the domain/postmaster mailbox
# (below), both via admin_cli's direct MySQL connection, not through any
# rendered config file. render-config.sh (every start, not just this one)
# does the actual substitution - run it now so postfix/dovecot/sogo/etc.
# have real config the first time supervisord starts them too.
/usr/local/lib/iredmail/render-config.sh

echo "*** first start: creating ${MAIL_DOMAIN} and postmaster@${MAIL_DOMAIN} (fixes #47: only if absent)"
POSTMASTER_PASSWORD="${POSTMASTER_PASSWORD:-}"
if [ -n "${POSTMASTER_PASSWORD_FILE:-}" ] && [ -f "$POSTMASTER_PASSWORD_FILE" ]; then
    POSTMASTER_PASSWORD="$(cat "$POSTMASTER_PASSWORD_FILE")"
fi
[ -z "$POSTMASTER_PASSWORD" ] && { echo "FATAL: POSTMASTER_PASSWORD or POSTMASTER_PASSWORD_FILE is required on first start" >&2; exit 1; }

mysql -uadmin_cli -p"${ADMIN_CLI_PW}" -h127.0.0.1 vmail -N -e \
    "SELECT 1 FROM domain WHERE domain='${MAIL_DOMAIN}';" | grep -q 1 || \
    /usr/local/bin/admin domain add "$MAIL_DOMAIN" >/dev/null

mysql -uadmin_cli -p"${ADMIN_CLI_PW}" -h127.0.0.1 vmail -N -e \
    "SELECT 1 FROM mailbox WHERE username='postmaster@${MAIL_DOMAIN}';" | grep -q 1 || {
    /usr/local/bin/admin user add "postmaster@${MAIL_DOMAIN}" --password "$POSTMASTER_PASSWORD" --quota 1G >/dev/null
    mysql -uroot -p"${MYSQL_ROOT_PW}" vmail -e \
        "UPDATE mailbox SET isadmin=1, isglobaladmin=1 WHERE username='postmaster@${MAIL_DOMAIN}';"
    mysql -uroot -p"${MYSQL_ROOT_PW}" vmail -e \
        "INSERT INTO domain_admins (username, domain, created) VALUES ('postmaster@${MAIL_DOMAIN}', 'ALL', NOW());"
}

# migrations bookkeeping (kept forward-compatible: legacy mysql/upgrades/ idea)
mysql -uroot -p"${MYSQL_ROOT_PW}" vmail -e \
    "CREATE TABLE IF NOT EXISTS versions (component VARCHAR(64) PRIMARY KEY, version INT NOT NULL);
     INSERT INTO versions (component, version) VALUES ('image', 1) ON DUPLICATE KEY UPDATE version=version;"

mysqladmin -uroot -p"${MYSQL_ROOT_PW}" shutdown
mkdir -p "$SECRETS_DIR"
touch "${SECRETS_DIR}/.initialized"
echo "*** first start: done"
