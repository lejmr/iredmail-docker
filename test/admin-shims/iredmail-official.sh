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
#   admin dkim show <domain>               -> the DKIM DNS record only
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
DKIM_CONF_DIR=/etc/amavis/conf.d
STORAGE_BASE=/var/vmail

sql() { mysql --defaults-file="$MY_CNF" vmail -N -B -e "$1"; }

# size like 1G / 500M -> MB integer (vmail.quota / mailbox.quota are in bytes
# in some iRedMail releases and MB in others; this image's mailbox.quota
# column is bytes, so convert to bytes here).
to_bytes() {
    local v="$1"
    case "$v" in
        *G|*g) echo $(( ${v%[Gg]} * 1024 * 1024 * 1024 )) ;;
        *M|*m) echo $(( ${v%[Mm]} * 1024 * 1024 )) ;;
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
    cat > "${DKIM_CONF_DIR}/60-admin-shim-${domain}" <<EOF
dkim_key("${domain}", "dkim", "${DKIM_DIR}/${domain}.pem");
EOF
    restart_amavis
    sleep 1

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
    rm -f "${DKIM_DIR}/${domain}.pem" "${DKIM_CONF_DIR}/60-admin-shim-${domain}"
    restart_amavis
}

cmd_domain_list() { sql "SELECT domain FROM domain;"; }

cmd_dkim_show() { /usr/sbin/amavisd-new showkeys "$1" 2>/dev/null; }

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
    local hash quota_bytes maildir date
    hash="$(doveadm pw -s CRYPT -p "$password")"
    quota_bytes="$(to_bytes "$quota")"
    date="$(date +%Y.%m.%d.%H.%M.%S)"
    maildir="${domain}/${username}-${date}/"

    sql "INSERT INTO mailbox (username, password, name, storagebasedirectory,
             storagenode, maildir, quota, domain, active, passwordlastchange, created, modified)
         VALUES ('${mail}', '${hash}', '${username}', '${STORAGE_BASE}',
             'vmail1', '${maildir}', ${quota_bytes}, '${domain}', 1, NOW(), NOW(), NOW());
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
    local mail="$1" quota_bytes
    quota_bytes="$(to_bytes "$2")"
    sql "UPDATE mailbox SET quota=${quota_bytes} WHERE username='${mail}';"
}

cmd_backup() {
    local tmp; tmp="$(mktemp -d)"
    mysqldump --defaults-file="$MY_CNF" vmail > "${tmp}/vmail.sql"
    tar -cf - -C "$tmp" vmail.sql \
        -C "$(dirname "$DKIM_DIR")" "$(basename "$DKIM_DIR")" \
        -C "$STORAGE_BASE" . 2>/dev/null
    rm -rf "$tmp"
}

cmd_restore() {
    local tmp; tmp="$(mktemp -d)"
    tar -xf - -C "$tmp"
    mysql --defaults-file="$MY_CNF" vmail < "${tmp}/vmail.sql"
    mkdir -p "$(dirname "$DKIM_DIR")"
    cp -a "${tmp}/$(basename "$DKIM_DIR")/." "$DKIM_DIR/" 2>/dev/null || true
    # everything else in the tar that isn't vmail.sql/dkim is maildir content
    for f in "$tmp"/*; do
        b="$(basename "$f")"
        [ "$b" = "vmail.sql" ] && continue
        [ "$b" = "$(basename "$DKIM_DIR")" ] && continue
        cp -a "$f" "$STORAGE_BASE/" 2>/dev/null || true
    done
    rm -rf "$tmp"
    restart_amavis
    supervisorctl restart dovecot postfix >/dev/null 2>&1 || true
}

group="${1:-}"; action="${2:-}"; shift 2 || true
case "${group} ${action}" in
    "domain add")   cmd_domain_add "$@" ;;
    "domain rm")    cmd_domain_rm "$@" ;;
    "domain list")  cmd_domain_list ;;
    "dkim show")    cmd_dkim_show "$@" ;;
    "user add")     cmd_user_add "$@" ;;
    "user rm")      cmd_user_rm "$@" ;;
    "user quota")   cmd_user_quota "$@" ;;
    "backup ")      cmd_backup ;;
    "restore ")     cmd_restore ;;
    *) echo "usage: admin domain add|rm|list ; admin user add|rm|quota ; admin dkim show ; admin backup ; admin restore" >&2; exit 2 ;;
esac
