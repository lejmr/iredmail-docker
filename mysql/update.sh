#!/bin/bash

echo "+++ Backing up vmail database"
mysqldump vmail -r /var/vmail/backup/mysql/vmail-0.9.6.sql

echo +++ Update SQL vmail structure
tmpf=$(tempfile)
echo "
CREATE TABLE IF NOT EXISTS alias_moderators (
    id BIGINT(20) UNSIGNED AUTO_INCREMENT,
    address VARCHAR(255) NOT NULL DEFAULT '',
    moderator VARCHAR(255) NOT NULL DEFAULT '',
    domain VARCHAR(255) NOT NULL DEFAULT '',
    dest_domain VARCHAR(255) NOT NULL DEFAULT '',
    PRIMARY KEY (id),
    UNIQUE INDEX (address, moderator),
    INDEX (domain),
    INDEX (dest_domain)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS forwardings (
    id BIGINT(20) UNSIGNED AUTO_INCREMENT,
    address VARCHAR(255) NOT NULL DEFAULT '',
    forwarding VARCHAR(255) NOT NULL DEFAULT '',
    domain VARCHAR(255) NOT NULL DEFAULT '',
    dest_domain VARCHAR(255) NOT NULL DEFAULT '',
    -- defines whether it's a standalone mail alias account. 0=no, 1=yes.
    is_list TINYINT(1) NOT NULL DEFAULT 0,
    -- defines whether it's a mail forwarding address of mail user. 0=no, 1=yes.
    is_forwarding TINYINT(1) NOT NULL DEFAULT 0,
    -- defines whether it's a per-account alias address. 0=no, 1=yes.
    is_alias TINYINT(1) NOT NULL DEFAULT 0,
    active TINYINT(1) NOT NULL DEFAULT 1,
    PRIMARY KEY (id),
    UNIQUE INDEX (address, forwarding),
    INDEX (domain),
    INDEX (dest_domain),
    INDEX (is_list),
    INDEX (is_alias)
) ENGINE=InnoDB;" > $tmpf
mysql -u root vmail < $tmpf
rm $tmpf

echo +++ Migrate mail accounts
python /opt/iredmail/tools/migrate_sql_alias_table.py

echo +++ Drop unused SQL columns and records in vmail.alias table
tmpf=$(tempfile)
echo "
DELETE FROM alias WHERE islist <> 1;
DELETE FROM alias WHERE address=domain;
ALTER TABLE alias DROP COLUMN goto;
ALTER TABLE alias DROP COLUMN moderators;
ALTER TABLE alias DROP COLUMN islist;
ALTER TABLE alias DROP COLUMN is_alias;
ALTER TABLE alias DROP COLUMN alias_to;" > $tmpf
mysql -u root vmail < $tmpf
rm $tmpf

echo +++ Update iRedAPD
cd /opt/iRedAPD-2.1/tools
bash upgrade_iredapd.sh
