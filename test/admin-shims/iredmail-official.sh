#!/bin/bash
# admin - the management contract the acceptance suite talks to.
#
# This is a SHIM: the official iredmail/mariadb:stable image ships no `admin`
# CLI (github.com/iredmail/dockerized, archived, BETA). It only exposes a web
# admin (iRedAdmin), a MySQL "vmail" database (classic iRedMail schema:
# domain/mailbox/alias/forwardings tables), doveadm, and amavisd-new (which
# also does DKIM signing/keygen - there is no opendkim in this image).
# This script implements the `admin` contract documented in ACCEPTANCE.md on
# top of exactly those pieces, so the suite can run unmodified against any
# image that honours the contract (this one, phase A, phase B, ...).
#
# It is mounted read-only into the container at /usr/local/bin/admin and run
# as root inside the container - NOT from the test suite's host process. The
# test suite's only exec permission is `docker compose exec <svc> admin ...`.
#
# Contract (stdout is the only interface the tests parse):
#   admin domain add <domain>              -> prints "MX: ..." and the DKIM
#                                              DNS record (as amavisd prints it)
#   admin domain rm <domain>
#   admin domain list                      -> one domain per line
#   admin dkim <domain>                    -> the DKIM DNS TXT record only
#   admin user add <email> --password P --quota <size>[G|M]
#   admin user rm <email>
#   admin user quota <email> <size>[G|M]
#   admin backup                           -> tar of vmail DB + DKIM keys + mail on stdout
#   admin restore                          -> reads that tar on stdin
#
# Exit 0 on success, non-zero + message on stderr on failure.
set -euo pipefail

MY_CNF=/root/.my.cnf
DKIM_DIR=/opt/iredmail/custom/amavisd/dkim
# amavisd is started as `amavisd-new -c /etc/amavis/conf.d/50-user`, which is
# a single file, not a directory glob; 50-user's own tail does
# `include_optional_config_files('/opt/iredmail/custom/amavisd/amavisd.conf')`
# - that is the documented, image-supported extension point, so new
# dkim_key() lines go there (one per line, tagged so `domain rm` can strip
# just its own line).
CUSTOM_AMAVISD_CONF=/opt/iredmail/custom/amavisd/amavisd.conf
STORAGE_BASE=/var/vmail

sql() { mysql --defaults-file="$MY_CNF" vmail -N -B -e "$1"; }

# size like 1G / 500M -> KB integer. Verified empirically (GETQUOTA on a
# user created with a known size): mailbox.quota is read by dovecot-sql as
# KILOBYTES, not bytes and not MB - a byte-unit value here silently produces
# a quota 1024x too large.
to_kb() {
    local v="$1"
    case "$v" in
        *G|*g) echo $(( ${v%[Gg]} * 1024 * 1024 )) ;;
        *M|*m) echo $(( ${v%[Mm]} * 1024 )) ;;
        *)     echo "$v" ;;
    esac
}

restart_amavis() { supervisorctl restart amavisd >/dev/null 2>&1 || true; }

cmd_domain_add() {
    local domain="$1"
    sql "INSERT INTO domain (domain, mailboxes, maxquota, quota, transport, created, modified, active)
         VALUES ('${domain}', 0, 0, 0, 'dovecot', NOW(), NOW(), 1);"

    mkdir -p "$DKIM_DIR"
    /usr/sbin/amavisd-new genrsa "${DKIM_DIR}/${domain}.pem" 1024 >/dev/null 2>&1
    chown amavis:amavis "${DKIM_DIR}/${domain}.pem"
    chmod 400 "${DKIM_DIR}/${domain}.pem"

    mkdir -p "$(dirname "$CUSTOM_AMAVISD_CONF")"
    touch "$CUSTOM_AMAVISD_CONF"
    grep -qF "admin-shim:${domain}" "$CUSTOM_AMAVISD_CONF" || \
        echo "dkim_key(\"${domain}\", \"dkim\", \"${DKIM_DIR}/${domain}.pem\"); # admin-shim:${domain}" \
            >> "$CUSTOM_AMAVISD_CONF"

    restart_amavis
    for i in $(seq 1 10); do
        /usr/sbin/amavisd-new showkeys "${domain}" 2>/dev/null | grep -q DKIM1 && break
        sleep 1
    done

    echo "MX: 10 ${HOSTNAME}"
    /usr/sbin/amavisd-new showkeys "${domain}" 2>/dev/null
}

cmd_domain_rm() {
    local domain="$1"
    for u in $(sql "SELECT username FROM mailbox WHERE domain='${domain}';"); do
        rm -rf "${STORAGE_BASE}/$(sql "SELECT maildir FROM mailbox WHERE username='${u}';")" 2>/dev/null || true
    done
    sql "DELETE FROM mailbox WHERE domain='${domain}';
         DELETE FROM forwardings WHERE domain='${domain}';
         DELETE FROM alias WHERE domain='${domain}';
         DELETE FROM domain_admins WHERE domain='${domain}';
         DELETE FROM domain WHERE domain='${domain}';"
    rm -f "${DKIM_DIR}/${domain}.pem"
    [ -f "$CUSTOM_AMAVISD_CONF" ] && sed -i "/# admin-shim:${domain}$/d" "$CUSTOM_AMAVISD_CONF"
    restart_amavis
}

cmd_domain_list() { sql "SELECT domain FROM domain;"; }

# Normalized to the same one-line "dkim._domainkey.<domain>.  IN TXT
# "<value>"" form the native CLI (image/scripts/admin) prints - amavisd-new
# showkeys wraps long keys across multiple quoted/parenthesized lines; the
# suite (test/conftest.py's DNS sidecar fixture, row17's key comparison)
# only ever needs the one TXT value, not amavisd's own formatting.
cmd_dkim() {
    local domain="$1" raw value
    raw="$(/usr/sbin/amavisd-new showkeys "$domain" 2>/dev/null)"
    value="$(printf '%s' "$raw" | grep -o '"[^"]*"' | tr -d '"\n')"
    echo "dkim._domainkey.${domain}.  IN TXT \"${value}\""
}

cmd_user_add() {
    local mail="$1"; shift
    local password="" quota="1G"
    while [ $# -gt 0 ]; do
        case "$1" in
            --password) password="$2"; shift 2 ;;
            --quota) quota="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    [ -n "$password" ] || { echo "admin user add: --password is required" >&2; exit 2; }

    local username="${mail%@*}" domain="${mail#*@}"
    local hash quota_kb maildir date
    hash="$(doveadm pw -s CRYPT -p "$password")"
    quota_kb="$(to_kb "$quota")"
    date="$(date +%Y.%m.%d.%H.%M.%S)"
    maildir="${domain}/${username}-${date}/"

    sql "INSERT INTO mailbox (username, password, name, storagebasedirectory,
             storagenode, maildir, quota, domain, active, passwordlastchange, created, modified)
         VALUES ('${mail}', '${hash}', '${username}', '${STORAGE_BASE}',
             'vmail1', '${maildir}', ${quota_kb}, '${domain}', 1, NOW(), NOW(), NOW());
         INSERT INTO forwardings (address, forwarding, domain, dest_domain, is_forwarding)
         VALUES ('${mail}', '${mail}', '${domain}', '${domain}', 1);"
}

cmd_user_rm() {
    local mail="$1"
    local maildir
    maildir="$(sql "SELECT maildir FROM mailbox WHERE username='${mail}';")"
    [ -n "$maildir" ] && rm -rf "${STORAGE_BASE}/${maildir}" 2>/dev/null || true
    sql "DELETE FROM mailbox WHERE username='${mail}';
         DELETE FROM forwardings WHERE address='${mail}';"
}

cmd_user_quota() {
    local mail="$1" quota_kb
    quota_kb="$(to_kb "$2")"
    sql "UPDATE mailbox SET quota=${quota_kb} WHERE username='${mail}';"
}

CUSTOM_DIR="$(dirname "$DKIM_DIR")"  # /opt/iredmail/custom/amavisd: dkim/ keys + amavisd.conf

cmd_backup() {
    local tmp; tmp="$(mktemp -d)"
    mysqldump --defaults-file="$MY_CNF" vmail > "${tmp}/vmail.sql"
    mkdir -p "${tmp}/custom" "${tmp}/mail"
    cp -a "${CUSTOM_DIR}/." "${tmp}/custom/" 2>/dev/null || true
    cp -a "${STORAGE_BASE}/." "${tmp}/mail/" 2>/dev/null || true
    tar -cf - -C "$tmp" vmail.sql custom mail 2>/dev/null
    rm -rf "$tmp"
}

cmd_restore() {
    local tmp; tmp="$(mktemp -d)"
    tar -xf - -C "$tmp"
    mysql --defaults-file="$MY_CNF" vmail < "${tmp}/vmail.sql"
    mkdir -p "$CUSTOM_DIR"
    cp -a "${tmp}/custom/." "${CUSTOM_DIR}/" 2>/dev/null || true
    cp -a "${tmp}/mail/." "${STORAGE_BASE}/" 2>/dev/null || true
    rm -rf "$tmp"
    restart_amavis
    supervisorctl restart dovecot postfix >/dev/null 2>&1 || true
}

# Same shape as the native CLI's dispatcher (image/scripts/admin): a group
# word, then either a subcommand or - for dkim/backup/restore, which are not
# grouped - the command's own argument(s) directly.
usage() {
    echo "usage: admin domain add|rm|list ; admin user add|rm|quota ; admin dkim <domain> ; admin backup ; admin restore" >&2
}

cmd="${1:-}"; shift || true
case "$cmd" in
    domain)
        sub="${1:-}"; shift || true
        case "$sub" in
            add) cmd_domain_add "$@" ;;
            rm) cmd_domain_rm "$@" ;;
            list) cmd_domain_list ;;
            *) usage; exit 2 ;;
        esac ;;
    user)
        sub="${1:-}"; shift || true
        case "$sub" in
            add) cmd_user_add "$@" ;;
            rm) cmd_user_rm "$@" ;;
            quota) cmd_user_quota "$@" ;;
            *) usage; exit 2 ;;
        esac ;;
    dkim) cmd_dkim "${1:-}" ;;
    backup) cmd_backup ;;
    restore) cmd_restore ;;
    *) usage; exit 2 ;;
esac
