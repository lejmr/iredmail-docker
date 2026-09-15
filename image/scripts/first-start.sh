#!/bin/bash
# Runs once, the very first time a container boots against an empty
# /data/mysql (marker: /data/secrets/.initialized). Everything here must be
# idempotent-safe to re-source-but-not-re-run: entrypoint.sh only calls it
# when the marker is missing.
set -euo pipefail
. /usr/local/lib/iredmail/common.sh

MAIL_DOMAIN="${MAIL_DOMAIN:?MAIL_DOMAIN env var is required on first start}"
HOSTNAME_FQDN="${HOSTNAME_FQDN:-mail.${MAIL_DOMAIN}}"
BUILD_DOMAIN=build.invalid
BUILD_HOSTNAME=mail.build.invalid

echo "*** first start: initialising MariaDB datadir"
mkdir -p /data/mysql /run/mysqld
chown -R mysql:mysql /data/mysql /run/mysqld
mariadb-install-db --datadir=/data/mysql --user=mysql --skip-name-resolve >/dev/null

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
SOGO_SIEVE_PW="$(secret sogo_sieve.pw)"
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
CREATE USER IF NOT EXISTS 'sogo'@'127.0.0.1' IDENTIFIED BY '${SOGO_DB_PW}';
GRANT ALL PRIVILEGES ON sogo.* TO 'sogo'@'127.0.0.1';
GRANT SELECT ON vmail.* TO 'sogo'@'127.0.0.1';
CREATE USER IF NOT EXISTS 'iredapd'@'127.0.0.1' IDENTIFIED BY '${IREDAPD_DB_PW}';
GRANT SELECT ON vmail.* TO 'iredapd'@'127.0.0.1';
GRANT SELECT,INSERT,UPDATE,DELETE ON vmail.greylisting_whitelists TO 'iredapd'@'127.0.0.1';
-- least-privilege technical account for the admin CLI (#57): only vmail db.
CREATE USER IF NOT EXISTS 'admin_cli'@'127.0.0.1' IDENTIFIED BY '${ADMIN_CLI_PW}';
GRANT SELECT,INSERT,DELETE,UPDATE ON vmail.* TO 'admin_cli'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

echo "*** first start: substituting runtime secrets into config files"
for pair in \
    "TEMP_VMAIL_DB_BIND_PASSWD:$VMAIL_DB_BIND_PW" \
    "TEMP_VMAIL_DB_ADMIN_PASSWD:$VMAIL_DB_ADMIN_PW" \
    "TEMP_MYSQL_ROOT_PASSWD:$MYSQL_ROOT_PW" \
    "TEMP_AMAVISD_DB_PASSWD:$AMAVISD_DB_PW" \
    "TEMP_IREDADMIN_DB_PASSWD:$IREDADMIN_DB_PW" \
    "TEMP_SOGO_DB_PASSWD:$SOGO_DB_PW" \
    "TEMP_SOGO_SIEVE_MASTER_PASSWD:$SOGO_SIEVE_PW" \
    "TEMP_IREDAPD_DB_PASSWD:$IREDAPD_DB_PW" \
    "TEMP_MLMMJADMIN_API_AUTH_TOKEN:$(secret mlmmjadmin.pw)" \
; do
    placeholder="${pair%%:*}"; real="${pair#*:}"
    grep -rlZ -F "$placeholder" /etc /opt 2>/dev/null | xargs -0 -r sed -i "s#${placeholder}#${real}#g"
done

echo "*** first start: rewiring build-time placeholder hostname/domain -> ${HOSTNAME_FQDN}/${MAIL_DOMAIN}"
grep -rlZ -F "$BUILD_HOSTNAME" /etc /opt 2>/dev/null | xargs -0 -r sed -i "s#${BUILD_HOSTNAME}#${HOSTNAME_FQDN}#g"
grep -rlZ -F "$BUILD_DOMAIN" /etc /opt 2>/dev/null | xargs -0 -r sed -i "s#${BUILD_DOMAIN}#${MAIL_DOMAIN}#g"
hostname "$HOSTNAME_FQDN" 2>/dev/null || true
echo "$HOSTNAME_FQDN" > "${SECRETS_DIR}/hostname"

echo "*** first start: TLS certificate (self-signed, CN=${HOSTNAME_FQDN}) unless mounted"
if [ ! -s /data/certs/cert.pem ] || [ ! -s /data/certs/key.pem ]; then
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
        -subj "/CN=${HOSTNAME_FQDN}" \
        -keyout /data/certs/key.pem -out /data/certs/cert.pem >/dev/null 2>&1
    chmod 0600 /data/certs/key.pem
fi
mkdir -p /etc/ssl/private
ln -sf /data/certs/cert.pem /etc/ssl/certs/iRedMail.crt
ln -sf /data/certs/key.pem /etc/ssl/private/iRedMail.key

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
