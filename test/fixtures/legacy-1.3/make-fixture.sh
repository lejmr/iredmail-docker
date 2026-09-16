#!/bin/bash
# Reproduces dump.sql and vmail.tar in this directory from a real
# lejmr/iredmail:mysql-1.3-latest container. See MAKE.md for the narrative
# (including why message delivery falls back to writing Maildir files
# directly). Re-runnable; the suite does NOT depend on this script - it
# uses the checked-in dump.sql/vmail.tar so it never needs Docker Hub.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'docker rm -f legacy-old >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT

mkdir -p "$WORK/mysql" "$WORK/vmail" "$WORK/clamav"

echo "==> pulling the old image"
docker pull --platform linux/amd64 lejmr/iredmail:mysql-1.3-latest

echo "==> starting it (seccomp=unconfined/SYS_PTRACE - see MAKE.md)"
docker rm -f legacy-old >/dev/null 2>&1 || true
docker run -d --platform linux/amd64 --name legacy-old \
    -h mail.legacy.example \
    --security-opt seccomp=unconfined --cap-add SYS_PTRACE \
    -e MYSQL_ROOT_PASSWORD=rootpass123 \
    -e SOGO_WORKERS=1 -e TZ=UTC \
    -e 'POSTMASTER_PASSWORD={PLAIN}postmasterpass' \
    -v "$WORK/mysql:/var/lib/mysql" \
    -v "$WORK/vmail:/var/vmail" \
    -v "$WORK/clamav:/var/lib/clamav" \
    lejmr/iredmail:mysql-1.3-latest >/dev/null

echo "==> waiting for MySQL"
for _ in $(seq 1 60); do
    docker exec legacy-old mysqladmin -uroot -prootpass123 ping >/dev/null 2>&1 && break
    sleep 5
done
docker exec legacy-old mysqladmin -uroot -prootpass123 ping

echo "==> second domain, users, alias"
docker exec legacy-old mysql -uroot -prootpass123 vmail -e "
    INSERT INTO domain (domain, transport, settings, created)
    VALUES ('legacy2.example','dovecot','default_user_quota:1024;', NOW());"

docker exec legacy-old bash -c \
    "cd /opt/iredmail/tools && bash create_mail_user_SQL.sh alice@legacy.example 'AliceOldPass123'" \
    | sed "s/'1024', 'legacy.example'/'512', 'legacy.example'/" \
    | docker exec -i legacy-old mysql -uroot -prootpass123 vmail

docker exec legacy-old bash -c \
    "cd /opt/iredmail/tools && bash create_mail_user_SQL.sh bob@legacy2.example 'BobOldPass456'" \
    | docker exec -i legacy-old mysql -uroot -prootpass123 vmail

docker exec legacy-old mysql -uroot -prootpass123 vmail -e "
    INSERT INTO forwardings (address, forwarding, domain, dest_domain, is_forwarding)
    VALUES ('sales@legacy.example','alice@legacy.example','legacy.example','legacy.example',1);"

echo "==> reading back the hashed Maildir paths mysql just assigned"
read -r alice_maildir <<<"$(docker exec legacy-old mysql -uroot -prootpass123 vmail -N -e \
    "SELECT maildir FROM mailbox WHERE username='alice@legacy.example';")"
read -r bob_maildir <<<"$(docker exec legacy-old mysql -uroot -prootpass123 vmail -N -e \
    "SELECT maildir FROM mailbox WHERE username='bob@legacy2.example';")"

echo "==> writing messages as Maildir files directly (see MAKE.md step 3)"
docker exec legacy-old bash -c "
    set -e
    mk() { mkdir -p \"/var/vmail/vmail1/\$1/Maildir/cur\" \"/var/vmail/vmail1/\$1/Maildir/new\" \"/var/vmail/vmail1/\$1/Maildir/tmp\"; }
    mk '${alice_maildir%/}'
    mk '${bob_maildir%/}'
    i=1
    for subj in 'Legacy message 1 to alice' 'Legacy message 2 to alice' 'Legacy message 3 to alice'; do
        f=\"/var/vmail/vmail1/${alice_maildir%/}/Maildir/new/161826000\${i}.M00000\${i}P\${i}.mail.legacy.example:2,S\"
        cat > \"\$f\" <<EOF
Return-Path: <sender@example.net>
Delivered-To: alice@legacy.example
From: sender@example.net
To: alice@legacy.example
Subject: \$subj
Date: Mon, 16 Sep 2026 04:3\${i}:00 +0000
Message-Id: <legacy-alice-\${i}@example.net>
MIME-Version: 1.0
Content-Type: text/plain; charset=us-ascii

This is legacy body message number \$i for alice.
EOF
        i=\$((i+1))
    done
    f='/var/vmail/vmail1/${bob_maildir%/}/Maildir/new/1618260010.M000000P1.mail.legacy2.example:2,S'
    cat > \"\$f\" <<EOF
Return-Path: <sender@example.net>
Delivered-To: bob@legacy2.example
From: sender@example.net
To: bob@legacy2.example
Subject: Legacy message to bob
Date: Mon, 16 Sep 2026 04:30:10 +0000
Message-Id: <legacy-bob-1@example.net>
MIME-Version: 1.0
Content-Type: text/plain; charset=us-ascii

This is legacy body message for bob.
EOF
    chown -R vmail:vmail /var/vmail/vmail1
"

echo "==> mysqldump --all-databases + tar of /var/vmail"
docker exec legacy-old mysqldump -uroot -prootpass123 \
    --all-databases --single-transaction --no-tablespaces \
    > "$HERE/dump.sql"
docker exec legacy-old tar -C / -cf - var/vmail > "$HERE/vmail.tar"

echo "==> done: $HERE/dump.sql ($(du -h "$HERE/dump.sql" | cut -f1)), $HERE/vmail.tar ($(du -h "$HERE/vmail.tar" | cut -f1))"
