# Running the acceptance suite

```
bin/test.sh
```

Brings up two servers (A, B) from `test/compose.yaml`, waits for both to
report `healthy`, runs `pytest` with a JUnit report at
`test-results/junit.xml`, tears everything down (`compose down -v`) even on
failure. Exit code is pytest's.

## Against this repo's default pair (official iRedMail image)

Nothing to set - `test/compose.yaml` defaults `IMAGE` to
`iredmail/mariadb:stable` and boots A/B as `mail.a.example`/`mail.b.example`.
First boot under amd64 emulation on Apple Silicon is slow (10+ minutes);
`bin/test.sh` waits up to 15 minutes for both services to become healthy
before handing off to pytest.

## Against this repo's own image (phase A)

    IMAGE=iredmail-phase-a:dev bin/test.sh

The image must already be built (`docker compose -f ../compose.yaml build`,
or however the `iredmail-phase-a:dev` tag got built locally) -
`test/compose.yaml` never builds it, only runs the tag named by `IMAGE`.
`bin/test.sh` only adds the admin-shim overlay
(`test/compose.official-shim.yaml`) when `IMAGE` is unset or is
`iredmail/mariadb:stable`; for any other tag it runs `test/compose.yaml`
alone, so this image's own `/usr/local/bin/admin` (`image/scripts/admin`) is
what `docker compose exec mail-a admin ...` calls - nothing shadows it.

## Against any other two servers

The suite never assumes it is talking to a container it started. Set:

| Variable | Meaning | Default |
|---|---|---|
| `MAIL_A_HOST` / `MAIL_B_HOST` | reachable hostname/IP of each server | `127.0.0.1` |
| `MAIL_A_DOMAIN` / `MAIL_B_DOMAIN` | the mail domain each server serves | `a.example` / `b.example` |
| `ADMIN_A_PASSWORD` / `ADMIN_B_PASSWORD` | password for `postmaster@<domain>` | `TestPassw0rd1!` |
| `MAIL_A_PORT_SMTP` / `_SMTPS` / `_SUBMISSION` / `_IMAPS` / `_HTTPS` (and `_B_`) | port numbers if not the compose defaults | 12525/12465/12587/12993/12443, 22525/... |
| `COMPOSE_SERVICE_A` / `COMPOSE_SERVICE_B` | `docker compose` service name for `admin` exec | `mail-a` / `mail-b` |
| `IMAGE` | image:tag for A and B | `iredmail/mariadb:stable` |
| `IMAGE_NEXT` | a second tag to upgrade to for row 13; row 13 is skipped with a clear reason when unset | unset |

Then run `pytest test/` directly (skip `bin/test.sh`, which always drives
`test/compose.yaml`) against servers you started some other way - this
image, the phase-B stack, or a production-like pair. The suite only requires
that each server answers on SMTP/IMAP/HTTPS/ActiveSync/CalDAV and exposes
the `admin` management contract documented in
`test/admin-shims/iredmail-official.sh`'s header comment.

## CalDAV/CardDAV principal URL

SOGo's own DAV endpoint (row 12) is `/SOGo/dav/<user>/`, not the server
root - a `PROPFIND` there returns `calendar-home-set`/`addressbook-home-set`
pointing at `/SOGo/dav/<user>/Calendar/` and `.../Contacts/`. There is no
`/.well-known/caldav` redirect or DAV handler at `/` in this image's nginx
config; a client (and the test) must address `/SOGo/dav/<user>/` directly.

## The `admin` contract

The suite's only `docker compose exec` is `exec <service> admin <args...>`.
`admin` is the public management interface every phase must provide:
`domain add|rm|list`, `user add|rm|quota|passwd`, `dkim <domain>`,
`backup`/`restore`. This repo's own image ships it natively
(`image/scripts/admin`). The official iRedMail image has no such CLI, so
`test/admin-shims/iredmail-official.sh` implements the same contract on top
of what that image does offer (its vmail MySQL schema, `doveadm`, and
`amavisd-new`'s DKIM signing/keygen) and is bind-mounted into the container
at `/usr/local/bin/admin` by the `test/compose.official-shim.yaml` overlay
(`bin/test.sh` adds it automatically for `IMAGE=iredmail/mariadb:stable`,
the default). A future phase-B image should ship its own `admin` directly;
the suite does not care which, as long as `admin dkim <domain>` prints
exactly one line: `dkim._domainkey.<domain>.  IN TXT "<value>"` - both
`image/scripts/admin` and the shim normalize to this, and it is what the
DNS sidecar (below) parses.

## DNS sidecar

Row 6 needs both A -> B delivery *and* B's `Authentication-Results:
dkim=pass` to happen for real - not via a shortcut that only works inside
this test harness. `test/compose.yaml` runs a third service, `dns`
(`coredns/coredns:1.11.3`, pinned), that both `mail-a` and `mail-b` use as
their resolver (compose's `dns:` field) and that is authoritative for
`a.example`/`b.example`:

- **A and MX records are static** (`test/dns/db.example`, a BIND-style zone
  file checked into the repo, loaded by `test/dns/Corefile`'s `file`
  plugin) - the IPs match the fixed addresses the compose file assigns
  `mail-a`/`mail-b` (`172.30.0.10`/`.11`), so they're known before anything
  starts.
- **DKIM TXT records can't be static** - each container generates its own
  DKIM key pair the first time it starts (`image/scripts/first-start.sh` /
  the official image's `amavisd-new genrsa`), so the value doesn't exist
  until the server is up. `db.example` ends with `$INCLUDE
  /etc/coredns/generated/dkim.zone`, a second file (seeded in the repo as
  an empty placeholder so CoreDNS has something valid to load on first
  boot). The `dns_sidecar` fixture in `test/conftest.py` (session-scoped,
  autouse) runs once both servers are healthy: it calls `admin dkim
  a.example` / `admin dkim b.example` through the *same* public `admin`
  interface every other test uses (never a container-internal file read),
  writes the TXT values as BIND `TXT` records (split into `"..." "..."`
  255-byte character-strings the way a real long DKIM TXT record is) into
  `test/dns/generated/dkim.zone`, and runs `docker compose restart dns`.
  CoreDNS's `file` plugin has a `reload` option, but it only watches the
  top-level zone file's own mtime, not an `$INCLUDE`d one - verified
  empirically (rewriting just the included file was not picked up across
  several reload intervals) - so a restart is what actually applies it. It
  is fast: CoreDNS has no state to rebuild.
- **dnsmasq was tried first and dropped.** It's the more obvious choice for
  something this small, but its `--txt-record` local-data support is
  broken in the current pinned build (`4km3/dnsmasq:2.90-r3`, which
  actually ships dnsmasq 2.91): every TXT query for a locally configured
  name either fails with `config error is REFUSED (EDE: not ready)` when
  no upstream resolver is configured, or is silently forwarded upstream
  instead of being answered from local data once one is - reproduced with
  several minimal configs (bare `txt-record`, combined with `address=`,
  combined with `local=`) before giving up on it; `address=`/`mx-host=`
  worked fine throughout, only `txt-record=` was broken. CoreDNS answers
  A/MX/TXT alike from the same zone file with no such issue.

With this, A's outbound delivery to `bob@b.example` does a real MX lookup
(`b.example` -> `mail-b.b.example` -> `172.30.0.11`) through the sidecar,
and B's Rspamd/Amavis DKIM check verifies A's signature against the TXT
record the sidecar now serves - `dkim=pass` is the DNS sidecar's key doing
real work, not a hard-coded pass.

`PEER_DOMAINS` (`image/scripts/peer-domains.sh`, this repo's own image) is
deliberately **not** set in `test/compose.yaml`: it installs a Postfix
`transport_maps` entry that routes straight to the peer container by
hostname, bypassing MX lookup entirely - exactly the shortcut row 6 must
avoid here. It's still what the top-level `compose.yaml` (a single
self-contained two-node example, no DNS infrastructure) uses, and is still
needed there for the same reason it always was: without it, `permit_
mynetworks` doesn't trust the peer's IP and an unauthenticated path between
the two (not exercised by any required row) would be rejected.

Earlier note, still true, on why this isn't a plain compose network alias:
Docker Desktop forwards the host machine's own DNS search domains into a
container's `resolv.conf`, and Postfix's resolver tries
`b.example.<host's search domain>` *before* the bare name whenever the name
has fewer dots than `ndots` - some networks resolve that via a public
wildcard DNS record, silently sending mail toward a real, unrelated host on
the internet instead of the container next to it. Pointing `dns:` only at
the sidecar sidesteps the search-domain question entirely, rather than
relying on NSS "files" (`/etc/hosts`) ordering to dodge it as the previous
`extra_hosts`-based approach did.
