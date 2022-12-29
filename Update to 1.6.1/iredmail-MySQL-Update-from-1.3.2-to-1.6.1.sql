-- This will Update all the DB in Progressive with Versions from 1.3.2 --
-- Version 1.4.0 Update --

USE vmail;

-- (mlmmj) mailing list owners.
CREATE TABLE IF NOT EXISTS maillist_owners (
    id BIGINT(20) UNSIGNED AUTO_INCREMENT,
    -- email address of mailing list
    address VARCHAR(255) NOT NULL DEFAULT '',
    -- email address of owner
    owner VARCHAR(255) NOT NULL DEFAULT '',
    domain VARCHAR(255) NOT NULL DEFAULT '',
    -- domain part of owner email address
    dest_domain VARCHAR(255) NOT NULL DEFAULT '',
    PRIMARY KEY (id),
    UNIQUE INDEX (address, owner),
    INDEX (owner),
    INDEX (domain),
    INDEX (dest_domain)
) ENGINE=InnoDB;

-- Drop unused SQL columns
ALTER TABLE mailbox DROP COLUMN IF EXISTS `allowedsenders`;
ALTER TABLE mailbox DROP COLUMN IF EXISTS `rejectedsenders`;
ALTER TABLE mailbox DROP COLUMN IF EXISTS `allowedrecipients`;
ALTER TABLE mailbox DROP COLUMN IF EXISTS `rejectedrecipients`;

-- Version 1.4.1 Update

USE vmail;

ALTER TABLE mailbox ADD COLUMN IF NOT EXISTS `enablesogowebmail` CHAR(1) NOT NULL DEFAULT 'y';
ALTER TABLE mailbox ADD COLUMN IF NOT EXISTS `enablesogocalendar` CHAR(1) NOT NULL DEFAULT 'y';
ALTER TABLE mailbox ADD COLUMN IF NOT EXISTS `enablesogoactivesync` CHAR(1) NOT NULL DEFAULT 'y';

-- Version 1.4.1 SOGo Update

USE sogo;

DROP TABLE IF EXISTS users;
DROP VIEW IF EXISTS users;

USE sogo;

CREATE VIEW IF NOT EXISTS users (
            c_uid, c_name, c_password, c_cn,
            mail, domain,
            c_webmail, c_calendar, c_activesync)
  AS SELECT username, username, password, name,
            username, domain,
            enablesogowebmail, enablesogocalendar, enablesogoactivesync
       FROM vmail.mailbox
      WHERE enablesogo=1 AND active=1;

-- Version 1.4.2 Update

USE vmail;

-- Fix incorrect column types.
ALTER TABLE mailbox MODIFY COLUMN `enablesogowebmail` VARCHAR(1) NOT NULL DEFAULT 'y';
ALTER TABLE mailbox MODIFY COLUMN `enablesogocalendar` VARCHAR(1) NOT NULL DEFAULT 'y';
ALTER TABLE mailbox MODIFY COLUMN `enablesogoactivesync` VARCHAR(1) NOT NULL DEFAULT 'y';

-- Drop unused columns.
ALTER TABLE mailbox DROP COLUMN IF EXISTS `lastlogindate`;
ALTER TABLE mailbox DROP COLUMN IF EXISTS `lastloginipv4`;
ALTER TABLE mailbox DROP COLUMN IF EXISTS `lastloginprotocol`;

-- Version 1.5.2 SOGo Update

USE sogo;

DROP TABLE IF EXISTS sogo_sessions_folder;

-- Update DB Version to 1.6.1

USE vmail;

UPDATE versions SET version = '1.6.1' WHERE component LIKE 'iredmail';

-- Update Roundcubemail DB --

USE roundcubemail;
-- Table structure for table `collected_addresses`

CREATE TABLE IF NOT EXISTS `collected_addresses` (
 `address_id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT,
 `changed` datetime NOT NULL DEFAULT '1000-01-01 00:00:00',
 `name` varchar(255) NOT NULL DEFAULT '',
 `email` varchar(255) NOT NULL,
 `user_id` int(10) UNSIGNED NOT NULL,
 `type` int(10) UNSIGNED NOT NULL,
 PRIMARY KEY(`address_id`),
 CONSTRAINT `user_id_fk_collected_addresses` FOREIGN KEY (`user_id`)
   REFERENCES `users`(`user_id`) ON DELETE CASCADE ON UPDATE CASCADE,
 UNIQUE INDEX `user_email_collected_addresses_index` (`user_id`, `type`, `email`)
) ROW_FORMAT=DYNAMIC ENGINE=INNODB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Table structure for table `responses`

CREATE TABLE IF NOT EXISTS `responses` (
 `response_id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT,
 `user_id` int(10) UNSIGNED NOT NULL,
 `name` varchar(255) NOT NULL,
 `data` longtext NOT NULL,
 `is_html` tinyint(1) NOT NULL DEFAULT '0',
 `changed` datetime NOT NULL DEFAULT '1000-01-01 00:00:00',
 `del` tinyint(1) NOT NULL DEFAULT '0',
 PRIMARY KEY (`response_id`),
 CONSTRAINT `user_id_fk_responses` FOREIGN KEY (`user_id`)
   REFERENCES `users` (`user_id`) ON DELETE CASCADE ON UPDATE CASCADE,
 INDEX `user_responses_index` (`user_id`, `del`)
) ROW_FORMAT=DYNAMIC ENGINE=INNODB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
