"""Fixtures for the acceptance suite (ACCEPTANCE.md, rows 1-20).

Everything here talks to a mail server the way a user or a mail client
would: SMTP/IMAP/HTTPS/ActiveSync/CalDAV sockets, and the `admin` command
run *inside* the container - the only `docker compose exec` the suite is
allowed to use, and only that one command. `admin` is the public management
contract (see test/admin-shims/iredmail-official.sh for what backs it on the
official image); tests must never reach past it into config files or logs.

Settings come from the environment so the same suite runs against any two
servers - this repo's own image, the official iRedMail image, or a
hand-built phase-B stack. Defaults match test/compose.yaml.
"""
import imaplib
import os
import re
import ssl
import subprocess
import time

import pytest


def _env(name, default):
    return os.environ.get(name, default)


class Server:
    """One mail server under test, reached only through public ports."""

    def __init__(self, label, compose_service, host, domain, admin_password, ports):
        self.label = label
        self.compose_service = compose_service
        self.host = host
        self.domain = domain
        self.admin_password = admin_password
        self.ports = ports  # dict: smtp, smtps, submission, imaps, https

    @property
    def postmaster(self):
        return f"postmaster@{self.domain}"

    def admin(self, *args, input=None, timeout=60, check=True):
        """Run `admin <args...>` inside the container via docker compose exec.
        The ONLY exec the suite performs, and only this command."""
        cmd = ["docker", "compose", *COMPOSE_ARGS, "exec", "-T",
               self.compose_service, "admin", *args]
        return subprocess.run(cmd, input=input, capture_output=True,
                               timeout=timeout, check=check)

    def imap(self, timeout=30):
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        conn = imaplib.IMAP4_SSL(self.host, self.ports["imaps"], ssl_context=ctx)
        conn.sock.settimeout(timeout)
        return conn


COMPOSE_FILE = os.path.join(os.path.dirname(__file__), "compose.yaml")
# The admin-shim overlay is only correct for the official image (see
# test/compose.official-shim.yaml, test/README.md "The admin contract") -
# mirrors bin/test.sh's own selection so `pytest test/` run directly against
# a compose stack this file also drives picks the same files bin/test.sh did.
COMPOSE_ARGS = ["-f", COMPOSE_FILE]
if os.environ.get("IMAGE", "iredmail/mariadb:stable") == "iredmail/mariadb:stable":
    COMPOSE_ARGS += ["-f", os.path.join(os.path.dirname(__file__), "compose.official-shim.yaml")]


def _server(letter):
    default_host = "127.0.0.1"
    default_ports = {"a": dict(smtp=12525, smtps=12465, submission=12587, imaps=12993, https=12443),
                      "b": dict(smtp=22525, smtps=22465, submission=22587, imaps=22993, https=22443)}[letter]
    return Server(
        label=letter.upper(),
        compose_service=_env(f"COMPOSE_SERVICE_{letter.upper()}", f"mail-{letter}"),
        host=_env(f"MAIL_{letter.upper()}_HOST", default_host),
        domain=_env(f"MAIL_{letter.upper()}_DOMAIN", f"{letter}.example"),
        admin_password=_env(f"ADMIN_{letter.upper()}_PASSWORD", "TestPassw0rd1!"),
        ports={k: int(_env(f"MAIL_{letter.upper()}_PORT_{k.upper()}", v)) for k, v in default_ports.items()},
    )


@pytest.fixture(scope="session")
def server_a():
    return _server("a")


@pytest.fixture(scope="session")
def server_b():
    return _server("b")


@pytest.fixture
def fresh_user(request):
    """Create a user through `admin user add` and delete it through
    `admin user rm` afterwards - the suite creates everything it needs
    through the public management interface and cleans up after itself."""
    created = []

    def make(server, local_part, password="Passw0rd1!", quota="1G"):
        mail = f"{local_part}@{server.domain}"
        server.admin("user", "add", mail, "--password", password, "--quota", quota)
        created.append((server, mail))
        return mail, password

    yield make

    for server, mail in created:
        server.admin("user", "rm", mail, check=False)


@pytest.fixture
def fresh_domain(request):
    """Create a domain through `admin domain add`, delete it afterwards."""
    created = []

    def make(server, domain):
        out = server.admin("domain", "add", domain)
        created.append((server, domain))
        return out.stdout.decode()

    yield make

    for server, domain in created:
        server.admin("domain", "rm", domain, check=False)


# ------------------------------------------------------------- DNS sidecar --
# See test/compose.yaml (`dns` service, CoreDNS) and test/README.md "DNS
# sidecar". The static half (A/MX records) is checked in at
# test/dns/db.example; the dynamic half (DKIM TXT records) only exists once
# a server has generated its per-domain key at first start, so it is
# written here, after the servers are up, from what `admin dkim <domain>`
# prints - the same public interface the suite uses everywhere else, never
# a config file read from inside the container.
DNS_GENERATED_DIR = os.path.join(os.path.dirname(__file__), "dns", "generated")
DNS_GENERATED_ZONE = os.path.join(DNS_GENERATED_DIR, "dkim.zone")


def _dkim_txt_value(admin_output):
    """Pull the quoted TXT value out of `admin dkim <domain>` output:
    `dkim._domainkey.<domain>.  IN TXT "v=DKIM1; ..."` - both the native
    CLI (image/scripts/admin) and the official-image shim normalize to this
    one-line form."""
    text = admin_output.decode(errors="replace")
    m = re.search(r'"([^"]*)"', text)
    return m.group(1) if m else ""


def _dns_zone_txt_record(name, value, chunk=255):
    """A DNS TXT record's rdata is one or more <=255-byte character-strings
    concatenated; a 2048-bit RSA DKIM key's base64 is longer than that, so
    split it into multiple quoted strings on the same RR - standard BIND
    zone-file syntax, and CoreDNS's `file` plugin reassembles them the same
    way a real DNS TXT record with multiple strings works."""
    parts = [value[i:i + chunk] for i in range(0, len(value), chunk)] or [""]
    quoted = " ".join(f'"{p}"' for p in parts)
    return f"{name}.  IN TXT ( {quoted} )"


@pytest.fixture(scope="session", autouse=True)
def dns_sidecar(server_a, server_b):
    """Once both servers are up, read their DKIM TXT records through the
    public `admin dkim <domain>` interface and load them into the DNS
    sidecar (test/compose.yaml's `dns` service), so row 6's `dkim=pass` and
    A -> B delivery both go through a real DNS TXT/MX lookup.

    No-op when the suite is pointed at servers this harness did not start
    (COMPOSE_SERVICE_*/MAIL_*_HOST overridden - see test/README.md "Against
    any other two servers") - there is no `dns` service to populate there.
    """
    default_topology = (
        os.environ.get("COMPOSE_SERVICE_A") is None
        and os.environ.get("MAIL_A_HOST") is None
    )
    if not default_topology:
        yield
        return

    lines = []
    for server in (server_a, server_b):
        out = server.admin("dkim", server.domain)
        value = _dkim_txt_value(out.stdout)
        assert value, f"admin dkim {server.domain} printed no TXT value: {out.stdout!r}"
        lines.append(_dns_zone_txt_record(f"dkim._domainkey.{server.domain}", value))

    os.makedirs(DNS_GENERATED_DIR, exist_ok=True)
    with open(DNS_GENERATED_ZONE, "w") as f:
        f.write("\n".join(lines) + "\n")

    # CoreDNS's `file` plugin `reload` only watches the top-level zone
    # file's mtime, not this $INCLUDE'd one (verified empirically - a
    # rewrite here was not picked up within several reload intervals) - a
    # restart is the reliable way to pick up a changed included file, and
    # it is fast (CoreDNS has no state to rebuild).
    subprocess.run(["docker", "compose", "-f", COMPOSE_FILE, "restart", "dns"],
                    check=True, timeout=60)
    time.sleep(3)  # CoreDNS's own startup; no admin-only way to probe it

    yield


def wait_for_message(imap_conn, subject, timeout=30, mailbox="INBOX"):
    """Poll an already-logged-in IMAP connection for a message with the
    given Subject header. Returns the message UID, or None on timeout."""
    imap_conn.select(mailbox)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        typ, data = imap_conn.search(None, "SUBJECT", f'"{subject}"')
        if typ == "OK" and data and data[0]:
            return data[0].split()[-1]
        time.sleep(1)
        imap_conn.select(mailbox)
    return None
