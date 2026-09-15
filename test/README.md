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

## Against any other two servers

The suite never assumes it is talking to a container it started. Set:

| Variable | Meaning | Default |
|---|---|---|
| `MAIL_A_HOST` / `MAIL_B_HOST` | reachable hostname/IP of each server | `127.0.0.1` |
| `MAIL_A_DOMAIN` / `MAIL_B_DOMAIN` | the mail domain each server serves | `a.example` / `b.example` |
| `ADMIN_A_PASSWORD` / `ADMIN_B_PASSWORD` | password for `postmaster@<domain>` | `TestPassw0rd1!` |
| `MAIL_A_PORT_SMTP` / `_SMTPS` / `_SUBMISSION` / `_IMAPS` / `_HTTPS` (and `_B_`) | port numbers if not the compose defaults | 12525/12465/12587/12993/12443, 22525/... |
| `COMPOSE_SERVICE_A` / `COMPOSE_SERVICE_B` | `docker compose` service name for `admin` exec | `a` / `b` |
| `IMAGE` | image:tag for A and B | `iredmail/mariadb:stable` |
| `IMAGE_NEXT` | a second tag to upgrade to for row 13; row 13 is skipped with a clear reason when unset | unset |

Then run `pytest test/` directly (skip `bin/test.sh`, which always drives
`test/compose.yaml`) against servers you started some other way - this
image, the phase-B stack, or a production-like pair. The suite only requires
that each server answers on SMTP/IMAP/HTTPS/ActiveSync/CalDAV and exposes
the `admin` management contract documented in
`test/admin-shims/iredmail-official.sh`'s header comment.

## The `admin` contract

The suite's only `docker compose exec` is `exec <service> admin <args...>`.
`admin` is the public management interface every phase must provide:
`domain add|rm|list`, `user add|rm|quota`, `dkim show`, `backup`/`restore`.
The official iRedMail image has no such CLI, so
`test/admin-shims/iredmail-official.sh` implements the contract on top of
what that image does offer (its vmail MySQL schema, `doveadm`, and
`amavisd-new`'s DKIM signing/keygen) and is bind-mounted into the container
at `/usr/local/bin/admin`. A future phase-B image should ship its own
`admin` directly; the suite does not care which.

## A↔B routing without public DNS

Postfix in this image has no `relayhost` configured; for a recipient at
`b.example` it resolves `b.example` itself and, finding no MX record, falls
back to the domain's own A record per RFC 5321 - so making `a.example` and
`b.example` resolve to each other's container is enough, no `transport_maps`
needed.

The first attempt used a plain compose network alias (`aliases: [b.example]`)
and docker's embedded DNS, on the theory that a domain-name alias plus "no
MX -> fall back to A record" would just work. It didn't, on this host:
Docker Desktop forwards the host machine's own DNS search domains into the
container's `resolv.conf`, and glibc's/Postfix's resolver tries
`b.example.<host's search domain>` *before* the bare name whenever the name
has fewer dots than `ndots` - which some networks resolve via a public
wildcard DNS record, silently sending mail toward a real, unrelated host on
the internet instead of the container next to it. `dns_search: []` did not
fix it (Docker Desktop re-added the host's search list regardless).

`test/compose.yaml` instead gives A and B static IPs on a fixed subnet
(`172.30.0.10` / `.11`) and points each at the other with Compose's
`extra_hosts`. NSS "files" (`/etc/hosts`) has no search-suffix behaviour at
all and is consulted before DNS, so this is immune to the above - and it is
still a declarative Compose field, not a file edited inside the image.
