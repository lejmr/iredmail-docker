# iRedMail in a container

> **Recommendation from the maintainer (2026):** for a new mail server, use
> [Stalwart](https://stalw.art). It is a single, small, actively developed
> binary that covers what this image covers - multi-domain SMTP/IMAP with
> quotas, built-in spam filtering, DKIM/DMARC, CalDAV/CardDAV, a web admin -
> without carrying a full Linux distribution and eleven daemons around.
> This image exists for people who already run it: it is buildable and
> tested again, on a current base, and it gets weekly security rebuilds. It
> will not get new features.

An all-in-one [iRedMail](https://www.iredmail.org) mail server - Postfix,
Dovecot, MariaDB, Amavis + SpamAssassin (ClamAV optional), iRedAPD,
iRedAdmin, SOGo (ActiveSync, CalDAV/CardDAV), nginx - in one image on
`debian:13-slim`, supervised by supervisord, without `--privileged`.

## Run it

```yaml
services:
  mail:
    image: ghcr.io/lejmr/iredmail-docker:latest   # or a dated tag - see Releases
    hostname: mail.example.org
    environment:
      MAIL_DOMAIN: example.org
      POSTMASTER_PASSWORD: change-me            # or POSTMASTER_PASSWORD_FILE=/run/secrets/…
      TZ: Europe/Prague
      CLAMAV: "0"                               # "1" runs ClamAV (about 1 GB more RAM)
    ports: ["25:25", "465:465", "587:587", "993:993", "443:443", "80:80"]
    volumes:
      - mysql:/data/mysql
      - vmail:/data/vmail
      - certs:/data/certs        # cert.pem (full chain) + key.pem here to use real certificates
      - secrets:/data/secrets
      - overrides:/data/overrides
    cap_drop: [ALL]
    cap_add: [NET_BIND_SERVICE, CHOWN, SETUID, SETGID, DAC_OVERRIDE, FOWNER, SYS_CHROOT, KILL]
volumes: { mysql: {}, vmail: {}, certs: {}, secrets: {}, overrides: {} }
```

`docker compose up -d`, wait for `healthy`, then:

```
docker compose exec mail admin domain add example.org      # prints the MX and DKIM records to publish
docker compose exec mail admin user add alice@example.org --password '…' --quota 2G
```

Web admin: `https://mail.example.org/iredadmin/` (log in as
`postmaster@example.org`). SOGo: `/SOGo/`. ActiveSync:
`/Microsoft-Server-ActiveSync`.

All five volumes are **required**: the container refuses to start if one is
not mounted - it would otherwise write into an anonymous volume and lose
your mail on the next `docker compose down`.

## Manage it

`admin` is the management interface; it is also what the test suite drives.

```
admin domain add|rm|list <domain>
admin user add <addr> --password <p> --quota <1G|512M> | rm | list [domain] | quota <addr> <q> | passwd <addr> <p>
admin dkim <domain>                       # the DNS TXT record
admin backup > file.tar                   # SQL dumps + mail + DKIM keys + certificates
admin restore < file.tar                  # into an empty server
```

Configuration overrides that survive upgrades go into the `overrides`
volume: `postfix/main.cf.d/*.cf` (`key = value`, applied with `postconf -e`
at every start) and `dovecot/*.conf` (included by Dovecot). Details in
[DEVELOPMENT.md](DEVELOPMENT.md).

## Upgrade

Pull the new tag, `docker compose up -d`. Schema migrations run
automatically on start (the `versions` table in the `vmail` database records
what was applied). Coming from the **old CentOS 7 image (`mysql-1.3`,
`Update to 1.6.1`)**: the layout is different - take `mysqldump`s and a copy
of `/var/vmail` from the old container, start this image fresh, and restore
with `admin restore` from a tar in the layout `admin backup` produces
(described in DEVELOPMENT.md). Test on a copy first.

## What is tested

[`ACCEPTANCE.md`](ACCEPTANCE.md) lists twenty things a person running a
mail server expects, in their words, observable only from outside the
container. `test/` proves them against two servers started from nothing
that exchange mail through a private DNS with real MX and DKIM records. CI
runs the suite on every pull request and rebuilds the image weekly, so a
base-image security update or a broken upstream repository shows up before
a user reports it. Every release's notes record which rows pass and which
do not.

## Security

[SECURITY.md](SECURITY.md): what this image is responsible for, what the
refresh fixed, how to report a finding (privately, please).

## Development

[DEVELOPMENT.md](DEVELOPMENT.md): build, run the suite, verify a change,
release. Pull requests are welcome - one acceptance row per behaviour.
