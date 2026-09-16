# The row 21 fixture: a real `lejmr/iredmail:mysql-1.3` server

`dump.sql` and `vmail.tar` in this directory are not hand-built - they are a
`mysqldump --all-databases` and a `tar` of `/var/vmail`, taken from a real
`lejmr/iredmail:mysql-1.3-latest` container (Docker Hub, last pushed 2021),
running under `--platform linux/amd64` emulation. The suite (`admin
import-legacy`, `test_row21_import_from_old_image`) uses only these checked-in
files - it does not depend on Docker Hub or on this script.

Old image version, read from the container itself:

    # /opt/iredmail/iRedMail.tips
    Version:  1.3.2
    # built 2021.01.07.06.51.03

    # vmail.versions table
    iredmail  1.3.2

## Reproducing

`make-fixture.sh` in this directory replays the exact steps below. It is
re-runnable but not deterministic byte-for-byte (timestamps, DKIM-irrelevant
here since the old image never signed these test messages) - that is fine,
`import-legacy` and the test only depend on the *shape* of the data, not its
bytes.

1. Pull and run the old image, exactly per its own README
   (`git show refresh/foundation:README.md`):

       docker pull --platform linux/amd64 lejmr/iredmail:mysql-1.3-latest
       docker run -d --platform linux/amd64 --name legacy-old \
         -h mail.legacy.example \
         --security-opt seccomp=unconfined --cap-add SYS_PTRACE \
         -e MYSQL_ROOT_PASSWORD=rootpass123 \
         -e SOGO_WORKERS=1 -e TZ=UTC \
         -e 'POSTMASTER_PASSWORD={PLAIN}postmasterpass' \
         -v /tmp/legacy-fixture-work/mysql:/var/lib/mysql \
         -v /tmp/legacy-fixture-work/vmail:/var/vmail \
         -v /tmp/legacy-fixture-work/clamav:/var/lib/clamav \
         -p 40993:993 -p 40587:587 -p 40025:25 -p 40443:443 \
         lejmr/iredmail:mysql-1.3-latest

   `--security-opt seccomp=unconfined --cap-add SYS_PTRACE`: without it,
   Dovecot 2.2.36 (this CentOS 7 image's version) crashes its `log` and
   `auth` services with signal 5 (SIGTRAP) under this host's Rosetta-based
   amd64 emulation (Docker Desktop on Apple Silicon) - a translation gap
   for whatever syscall those services make on startup, not a bug in the
   image. Confirmed by bisecting: identical crash with `seccomp=unconfined`
   alone, gone with it added. Wait for MySQL (`mysqladmin ping`) and IMAP
   (993/tcp) to answer - the image has no healthcheck.

2. Through the old image's own tools (not this repo's `admin` - it does not
   exist on that image), create a second domain, two users and an alias:

       # second domain - the old schema has no `admin domain add`, this is
       # the same INSERT iRedMail's own installer would have run
       docker exec legacy-old mysql -uroot -prootpass123 vmail -e \
         "INSERT INTO domain (domain, transport, settings, created)
          VALUES ('legacy2.example','dovecot','default_user_quota:1024;', NOW());"

       # users - the old image's own /opt/iredmail/tools/create_mail_user_SQL.sh
       # (prints INSERT statements for mailbox + forwardings; quota edited
       # to 512 for alice after generation, to get a non-default quota)
       docker exec legacy-old bash -c \
         "cd /opt/iredmail/tools && bash create_mail_user_SQL.sh alice@legacy.example 'AliceOldPass123'" \
         | sed "s/'1024', 'legacy.example'/'512', 'legacy.example'/" \
         | docker exec -i legacy-old mysql -uroot -prootpass123 vmail
       docker exec legacy-old bash -c \
         "cd /opt/iredmail/tools && bash create_mail_user_SQL.sh bob@legacy2.example 'BobOldPass456'" \
         | docker exec -i legacy-old mysql -uroot -prootpass123 vmail

       # an alias (the old schema's `forwardings` table - same table this
       # image's Postfix virtual_alias_maps queries; a plain alias needs no
       # row in the separate `alias` table)
       docker exec legacy-old mysql -uroot -prootpass123 vmail -e \
         "INSERT INTO forwardings (address, forwarding, domain, dest_domain, is_forwarding)
          VALUES ('sales@legacy.example','alice@legacy.example','legacy.example','legacy.example',1);"

3. Deliver real messages with real headers. SMTP submission on 587 could
   not be used: Postfix/amavis kept restarting in a crash loop because the
   ClamAV volume mount (per the old README) shadows the image's built-in
   virus database with an empty directory, and amavis treats every
   `av-scanner FAILED` as fatal enough to bring the content filter down
   with it. `dovecot-lda` (the old image's own local-delivery binary,
   independent of Postfix/amavis) delivers directly:

       printf 'From: sender@example.net\nTo: alice@legacy.example\nSubject: Legacy message 1 to alice\nDate: ...\nMessage-Id: <legacy-alice-1@example.net>\n\nThis is legacy body message number 1 for alice.\n' \
         | docker exec -i legacy-old /usr/libexec/dovecot/dovecot-lda -d alice@legacy.example

   ... repeated for 3 messages to alice and 1 to bob. **This did not work
   either**, even with the seccomp fix from step 1: `dovecot-lda` needs the
   same `auth`/`config` services that were crashing, and under sustained
   load the throttled restart loop never stabilised long enough for a
   local-delivery auth lookup to complete (`userdb lookup: Disconnected
   unexpectedly`, `Couldn't connect to auth socket`). This is the one place
   this fixture is **not** literally "through the old image's own
   interfaces": the 4 messages were instead written directly as Maildir
   files in the same format `dovecot-lda` would have produced - real
   RFC822 headers (`Message-Id`, `Date`, `Return-Path`, `Delivered-To`,
   `Subject`), real Maildir naming (`<epoch>.M<usec>P<n>.<host>:2,S`), under
   the exact hashed-Maildir path the `mailbox.maildir` column records
   (`<domain>/<hash>/<user>-<ts>/Maildir/{cur,new,tmp}`, matching
   `mailboxfolder='Maildir'` from the `mailbox` table). What `import-legacy`
   and the test exercise is unaffected by this substitution: they read
   Maildir files by path from `vmail.tar`, the same whether Dovecot or this
   script wrote them.

4. Take the fixture from the container, not from any host bind-mount (so
   ownership/permissions inside the tar are exactly what a real backup
   would have):

       docker exec legacy-old mysqldump -uroot -prootpass123 \
         --all-databases --single-transaction --no-tablespaces \
         > test/fixtures/legacy-1.3/dump.sql
       docker exec legacy-old tar -C / -cf - var/vmail \
         > test/fixtures/legacy-1.3/vmail.tar

       docker rm -f legacy-old
       rm -rf /tmp/legacy-fixture-work

Fixture size: `dump.sql` ~580 KB, `vmail.tar` ~60 KB (well under the 2 MB
budget) - `--no-tablespaces` and only the handful of rows this scenario
needs keep the SQL dump small; the tar holds four short plain-text messages.

## What is deliberately in the fixture, and why

| Data | Purpose |
|---|---|
| `legacy.example` (pre-existing) + `legacy2.example` (added) | row 21's "every old domain" |
| `alice@legacy.example`, quota 512M (non-default) | password + Maildir content survive; "quotas unchanged" is meaningfully tested (default quota would pass even if the column were dropped) |
| `bob@legacy2.example` | a user on the *second* domain, not the domain that happened to be first |
| `sales@legacy.example` -> `alice@legacy.example` | an alias (`forwardings` row with `address != forwarding`) |
| 3 messages to alice, 1 to bob, distinct subjects | message *count* and *identity* both checked, not just "INBOX is non-empty" |
| `postmaster@legacy.example` (from the old image's own first boot) | exercises the domain-collision path when the *new* server's own initial domain happens to equal an imported one (tested manually during development; not the pytest fixture's primary domain, which uses `new.example` as the new server's initial domain to avoid the collision) |
