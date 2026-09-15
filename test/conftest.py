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
        cmd = ["docker", "compose", "-f", COMPOSE_FILE, "exec", "-T",
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


def _server(letter):
    default_host = "127.0.0.1"
    default_ports = {"a": dict(smtp=12525, smtps=12465, submission=12587, imaps=12993, https=12443),
                      "b": dict(smtp=22525, smtps=22465, submission=22587, imaps=22993, https=22443)}[letter]
    return Server(
        label=letter.upper(),
        compose_service=_env(f"COMPOSE_SERVICE_{letter.upper()}", letter),
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
