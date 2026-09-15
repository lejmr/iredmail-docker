#!/bin/bash
# Forward-only schema migrations, run on every start before services come
# up. Modelled on the legacy mysql/upgrades/ idea: numbered SQL files in
# migrations/, and a `versions` table (vmail db, created by first-start.sh)
# recording the last one applied. No migrations exist yet for this image
# (v1) - this is the hook the next image version runs through.
set -euo pipefail
. /usr/local/lib/iredmail/common.sh

MIGRATIONS_DIR=/usr/local/lib/iredmail/migrations
[ -d "$MIGRATIONS_DIR" ] || exit 0
ls "$MIGRATIONS_DIR"/*.sql >/dev/null 2>&1 || exit 0

mysqld_safe --datadir=/data/mysql --skip-networking=0 --bind-address=127.0.0.1 &
for _ in $(seq 1 60); do mysqladmin ping --silent 2>/dev/null && break; sleep 1; done

MYSQL_ROOT_PW="$(secret mysql_root.pw)"
current="$(mysql -uroot -p"$MYSQL_ROOT_PW" -N vmail -e \
    "SELECT version FROM versions WHERE component='image';" 2>/dev/null || echo 1)"

for f in $(ls "$MIGRATIONS_DIR"/*.sql | sort -V); do
    v="$(basename "$f" .sql)"
    if [ "$v" -gt "$current" ]; then
        mysql -uroot -p"$MYSQL_ROOT_PW" vmail < "$f"
        mysql -uroot -p"$MYSQL_ROOT_PW" vmail -e \
            "UPDATE versions SET version=${v} WHERE component='image';"
    fi
done

mysqladmin -uroot -p"$MYSQL_ROOT_PW" shutdown
