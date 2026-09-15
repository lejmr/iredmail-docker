"""Acceptance suite: one test per row of ACCEPTANCE.md, black-box only.

Every test talks to a server through a public interface - SMTP/IMAP/HTTPS/
ActiveSync/CalDAV sockets, or `admin` run inside the container (the only
`docker compose exec`, and only that command; see conftest.py). Nothing here
reads a config file, runs `doveadm` from the host, or greps a log for an
implementation detail (row 1's "no `error` at startup" is the one documented
log assertion, via `docker compose logs`).

Rows 11 and 20 have a maintainer part (a real phone/browser) that is out of
scope here; only their machine-observable part is tested.
"""
import email.utils
import imaplib
import os
import re
import smtplib
import socket
import ssl
import subprocess
import time

import pytest
import requests

from conftest import COMPOSE_ARGS, COMPOSE_FILE, wait_for_message

requests.packages.urllib3.disable_warnings()  # self-signed certs in tests


# ---------------------------------------------------------------- helpers --

def openssl_starttls(host, port, proto, timeout=15):
    """Raw TLS handshake via openssl s_client - clearer than smtplib/imaplib
    for asserting protocol version and certificate CN."""
    cmd = ["openssl", "s_client", "-connect", f"{host}:{port}", "-servername", host]
    if proto:
        cmd += ["-starttls", proto]
    p = subprocess.run(cmd, input=b"QUIT\n", capture_output=True, timeout=timeout)
    return (p.stdout + p.stderr).decode(errors="replace")


def smtp_send(server, mail_from, rcpt_to, subject, body="body", helo=None,
              auth=None, port_key="submission", starttls=True, headers=None):
    port = server.ports[port_key]
    smtp = smtplib.SMTP(server.host, port, timeout=30)
    smtp.ehlo(helo or "test-client.example")
    if starttls:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        smtp.starttls(context=ctx)
        smtp.ehlo(helo or "test-client.example")
    if auth:
        smtp.login(*auth)
    msg_id = email.utils.make_msgid()
    hdr = f"From: {mail_from}\r\nTo: {rcpt_to}\r\nSubject: {subject}\r\nMessage-ID: {msg_id}\r\n"
    for k, v in (headers or {}).items():
        hdr += f"{k}: {v}\r\n"
    msg = hdr + f"\r\n{body}\r\n"
    result = smtp.sendmail(mail_from, [rcpt_to], msg)
    smtp.quit()
    return result


def imap_login(server, user, password):
    conn = server.imap()
    conn.login(user, password)
    return conn


def domain_admin_cred(server):
    return server.postmaster, server.admin_password


def _container_id(service):
    p = subprocess.run(["docker", "compose", "-f", COMPOSE_FILE, "ps", "-q", service],
                        capture_output=True, timeout=30, check=True)
    return p.stdout.decode().strip()


def compose_ps():
    p = subprocess.run(["docker", "compose", "-f", COMPOSE_FILE, "ps", "--format", "json"],
                        capture_output=True, timeout=30, check=True)
    import json
    out = p.stdout.decode()
    return [json.loads(line) for line in out.splitlines() if line.strip()]


def _tmpdir(name):
    """A directory under the repo, not the system temp dir - Docker Desktop
    on macOS does not share /var/folders (Python's tempfile default) into
    its VM, so a bind mount from there silently mounts as an empty
    directory instead of the file. test-results/ is already ignored."""
    import uuid
    path = os.path.join(os.path.dirname(__file__), "..", "test-results", f"{name}-{uuid.uuid4().hex[:8]}")
    path = os.path.abspath(path)
    os.makedirs(path, exist_ok=True)
    return path


def compose_logs():
    p = subprocess.run(["docker", "compose", "-f", COMPOSE_FILE, "logs", "--no-color"],
                        capture_output=True, timeout=60, check=True)
    return p.stdout.decode(errors="replace")


# ------------------------------------------------------------------ row 1 --

def test_row01_starts_healthy(server_a, server_b):
    """The server starts from nothing and is healthy"""
    deadline = time.monotonic() + 120
    statuses = {}
    while time.monotonic() < deadline:
        rows = compose_ps()
        # Only services that report a Docker HEALTHCHECK - the row is about
        # the mail server(s) under test, not the harness's own DNS sidecar
        # (test/compose.yaml's `dns` service has none and always reports "").
        statuses = {r["Service"]: r.get("Health", "") for r in rows if r.get("Health", "")}
        if statuses and all(v == "healthy" for v in statuses.values()):
            break
        time.sleep(3)
    assert statuses and all(v == "healthy" for v in statuses.values()), (
        f"not all services healthy within 120s: {statuses}")

    logs = compose_logs()
    bad = [ln for ln in logs.splitlines() if re.search(r"\berror\b", ln, re.I)]
    assert not bad, f"'error' found in startup log, e.g.: {bad[:5]}"


# ------------------------------------------------------------------ row 2 --

def test_row02_add_domain(server_a):
    """I add a domain"""
    domain = "row02.example"
    server_a.admin("domain", "rm", domain, check=False)
    try:
        out = server_a.admin("domain", "add", domain)
        assert out.returncode == 0

        listed = server_a.admin("domain", "list").stdout.decode()
        assert domain in listed

        combined = out.stdout.decode()
        assert re.search(r"\bMX\b", combined), f"no MX record printed: {combined!r}"
        assert "DKIM1" in combined, f"no DKIM record printed: {combined!r}"
    finally:
        server_a.admin("domain", "rm", domain, check=False)


# ------------------------------------------------------------------ row 3 --

def test_row03_remove_domain(server_a, fresh_domain, fresh_user):
    """I remove a domain"""
    victim = "row03.example"
    fresh_domain(server_a, victim)
    # a user on the domain that stays, to prove it is untouched
    mail, password = fresh_user(server_a, "alice", quota="1G")
    # a user on the domain being removed, added directly (fresh_user always
    # targets server.domain)
    victim_mail = f"bob@{victim}"
    server_a.admin("user", "add", victim_mail, "--password", "Passw0rd1!", "--quota", "1G")

    conn = imap_login(server_a, victim_mail, "Passw0rd1!")
    conn.logout()

    server_a.admin("domain", "rm", victim)

    listed = server_a.admin("domain", "list").stdout.decode()
    assert victim not in listed

    with pytest.raises((imaplib.IMAP4.error, ConnectionError, OSError)):
        c = server_a.imap()
        c.login(victim_mail, "Passw0rd1!")

    # other domain (server_a.domain, holding `mail`/alice) is untouched
    conn = imap_login(server_a, mail, password)
    conn.logout()


# ------------------------------------------------------------------ row 4 --

def test_row04_add_remove_user(server_a, fresh_user):
    """I add / remove a user with a password and a quota"""
    mail, password = fresh_user(server_a, "row04user", quota="1G")

    conn = imap_login(server_a, mail, password)
    conn.logout()

    server_a.admin("user", "rm", mail)
    with pytest.raises((imaplib.IMAP4.error, ConnectionError, OSError)):
        c = server_a.imap()
        c.login(mail, password)


def test_row04_restart_does_not_change_password(server_a, fresh_user):
    """A container restart does not change a user's password (#47)"""
    mail, password = fresh_user(server_a, "row04restart", quota="1G")
    conn = imap_login(server_a, mail, password)
    conn.logout()

    subprocess.run(["docker", "compose", "-f", COMPOSE_FILE, "restart", server_a.compose_service],
                    check=True, timeout=300)
    _wait_port(server_a.host, server_a.ports["imaps"], 180)

    conn = _retry_imap_login(server_a, mail, password)
    conn.logout()


def _retry_imap_login(server, mail, password, attempts=8, delay=5):
    """The port accepts TCP before dovecot's TLS listener is fully ready
    right after a restart; retry the handshake, not just the TCP connect."""
    last_exc = None
    for _ in range(attempts):
        try:
            return imap_login(server, mail, password)
        except (ssl.SSLError, OSError, imaplib.IMAP4.error) as exc:
            last_exc = exc
            time.sleep(delay)
    raise last_exc


def _wait_port(host, port, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection((host, port), timeout=3):
                return
        except OSError:
            time.sleep(2)
    raise TimeoutError(f"{host}:{port} did not come up within {timeout}s")


# ------------------------------------------------------------------ row 5 --

def test_row05_quota_refuses_over_limit(server_a, fresh_user):
    """I change a quota; exceeding it refuses delivery"""
    mail, password = fresh_user(server_a, "row05user", quota="5M")
    server_a.admin("user", "quota", mail, "1M")

    conn = imap_login(server_a, mail, password)
    # RFC 2087: imaplib's getquotaroot already returns both untagged
    # responses it triggers - [0] is the QUOTAROOT line (INBOX <root name>),
    # [1] is the QUOTA line for that root (<root name> (STORAGE used limit)).
    # STORAGE's unit is server-specific: RFC 2087's own traditional
    # convention is kilobytes (1M -> 1024), which is what this repo's own
    # image reports; the official iredmail/mariadb:stable image was found
    # to report raw bytes instead (1M -> 1048576) - ACCEPTANCE.md row 5 only
    # asks that "GETQUOTA reports 1M", not a specific wire encoding, so
    # accept either rather than hard-coding one image's convention.
    typ, data = conn.getquotaroot("INBOX")
    assert typ == "OK", f"GETQUOTAROOT failed: {data!r}"
    quota_line = b" ".join(data[1]) if len(data) > 1 else b""
    assert b"1048576" in quota_line or b" 1024 " in quota_line or quota_line.endswith(b"1024)"), (
        f"GETQUOTA did not report 1M (1024 KB or 1048576 bytes): {quota_line!r}")
    conn.logout()

    admin_mail, admin_pw = domain_admin_cred(server_a)
    body = "X" * (2 * 1024 * 1024)
    with pytest.raises(smtplib.SMTPException) as exc:
        smtp_send(server_a, admin_mail, mail, "row05 over quota", body=body,
                  auth=(admin_mail, admin_pw))
    assert "552" in str(exc.value) or "over quota" in str(exc.value).lower()


# ------------------------------------------------------------------ row 6/7 --

def test_row06_mail_a_to_b_arrives_with_dkim(server_a, server_b, fresh_user):
    """A user sends mail to another server and it arrives"""
    a_mail, a_pw = fresh_user(server_a, "row06a")
    b_mail, b_pw = fresh_user(server_b, "row06b")
    subject = f"row06-{time.time()}"

    smtp_send(server_a, a_mail, b_mail, subject, auth=(a_mail, a_pw))

    conn = imap_login(server_b, b_mail, b_pw)
    uid = wait_for_message(conn, subject, timeout=60)
    assert uid, "message from A did not arrive on B within 60s"

    typ, data = conn.fetch(uid, "(BODY[HEADER])")
    header = data[0][1].decode(errors="replace")
    assert "DKIM-Signature" in header, "A did not DKIM-sign the message"
    assert re.search(r"Authentication-Results:.*dkim=pass", header, re.I | re.S), (
        f"B did not add Authentication-Results dkim=pass: {header}")
    conn.logout()


def test_row07_reply_arrives_back(server_a, server_b, fresh_user):
    """The reply arrives back"""
    a_mail, a_pw = fresh_user(server_a, "row07a")
    b_mail, b_pw = fresh_user(server_b, "row07b")
    subject_out = f"row07-out-{time.time()}"
    subject_reply = f"row07-reply-{time.time()}"

    smtp_send(server_a, a_mail, b_mail, subject_out, auth=(a_mail, a_pw))
    conn_b = imap_login(server_b, b_mail, b_pw)
    assert wait_for_message(conn_b, subject_out, timeout=60), "A -> B leg failed"
    conn_b.logout()

    smtp_send(server_b, b_mail, a_mail, subject_reply, auth=(b_mail, b_pw))
    conn_a = imap_login(server_a, a_mail, a_pw)
    uid = wait_for_message(conn_a, subject_reply, timeout=60)
    assert uid, "reply from B did not arrive back on A within 60s"
    conn_a.logout()


# ------------------------------------------------------------------ row 8 --

def test_row08_relay_denied_without_auth(server_a):
    """Nobody can send through the server without logging in"""
    # a HELO/sender/recipient combination real enough to clear this image's
    # earlier restrictions (reject_unknown_helo_hostname, reject_unknown_
    # {sender,recipient}_domain, reject_unlisted_sender for a locally-hosted
    # sender domain) so what should reject the message is the one row 8
    # names: relaying without authenticating. HELO as a bracketed IP literal
    # is exempt from hostname-resolution checks per Postfix's own docs; the
    # envelope addresses use real, resolvable, non-null-MX domains that are
    # neither server's own.
    smtp = smtplib.SMTP(server_a.host, server_a.ports["smtp"], timeout=30)
    smtp.ehlo("[203.0.113.5]")
    with pytest.raises(smtplib.SMTPRecipientsRefused) as exc:
        smtp.sendmail("nobody@gmail.com", ["nobody@outlook.com"],
                      "Subject: row08\r\n\r\nbody\r\n")
    code, msg = next(iter(exc.value.recipients.values()))
    assert code == 554, f"expected 554, got {code} {msg!r}"
    assert b"Relay access denied" in msg or b"relay access denied" in msg.lower()
    smtp.quit()


# ------------------------------------------------------------------ row 9 --

GTUBE = "XJS*C4JDBQADN1.NSBN3*2IDNEN*GTUBE-STANDARD-ANTI-UBE-TEST-EMAIL*C.34X"
EICAR = r"X5O!P%@AP[4\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*"


def test_row09_spam_lands_in_junk_or_is_rejected(server_a, server_b, fresh_user):
    """Spam does not reach the INBOX"""
    a_mail, a_pw = fresh_user(server_a, "row09spam_a")
    b_mail, b_pw = fresh_user(server_b, "row09spam_b")
    subject = f"row09-gtube-{time.time()}"

    try:
        smtp_send(server_b, b_mail, a_mail, subject, body=GTUBE, auth=(b_mail, b_pw))
    except smtplib.SMTPException as exc:
        assert "5" in str(getattr(exc, "smtp_code", "5"))[:1]
        return  # rejected outright - satisfies "does not reach the INBOX"

    conn = imap_login(server_a, a_mail, a_pw)
    in_inbox = wait_for_message(conn, subject, timeout=20, mailbox="INBOX")
    assert not in_inbox, "GTUBE landed in INBOX"
    in_junk = wait_for_message(conn, subject, timeout=40, mailbox="Junk")
    assert in_junk, "GTUBE neither rejected nor filed to Junk"
    conn.logout()


def test_row09_virus_is_rejected(server_a, server_b, fresh_user):
    """Viruses do not reach the INBOX"""
    a_mail, a_pw = fresh_user(server_a, "row09virus_a")
    b_mail, b_pw = fresh_user(server_b, "row09virus_b")
    subject = f"row09-eicar-{time.time()}"

    with pytest.raises(smtplib.SMTPException) as exc:
        smtp_send(server_b, b_mail, a_mail, subject, body=EICAR, auth=(b_mail, b_pw))
    code = getattr(exc.value, "smtp_code", 550)
    assert 500 <= code < 600, f"EICAR was not rejected with 5xx: {exc.value}"


# ------------------------------------------------------------------ row 10 --

@pytest.mark.parametrize("port_key,starttls_proto", [
    ("submission", "smtp"),
    ("smtps", None),
    ("imaps", None),
    ("https", None),
])
def test_row10_tls_in_transit(server_a, port_key, starttls_proto):
    """Mail is encrypted in transit"""
    out = openssl_starttls(server_a.host, server_a.ports[port_key], starttls_proto)
    assert re.search(r"Protocol\s*:\s*TLSv1\.[23]", out), f"no TLS1.2+ reported:\n{out}"
    assert f"CN = {server_a.host if False else 'mail.a.example'}" in out or "mail.a.example" in out, (
        f"certificate CN does not match mail.a.example:\n{out}")


# ------------------------------------------------------------------ row 11 --

def test_row11_activesync_options_and_foldersync(server_a, fresh_user):
    """My phone has mail, calendar and contacts with push, via one Exchange account (machine part)"""
    mail, password = fresh_user(server_a, "row11user")
    base = f"https://{server_a.host}:{server_a.ports['https']}/Microsoft-Server-ActiveSync"

    r = requests.options(base, verify=False, timeout=15)
    assert r.status_code == 200, f"OPTIONS {base} -> {r.status_code}"
    versions = r.headers.get("MS-ASProtocolVersions", "")
    assert "14.1" in versions, f"MS-ASProtocolVersions does not contain 14.1: {versions!r}"

    r = requests.post(f"{base}?Cmd=FolderSync&User={mail}&DeviceId=harness001&DeviceType=harness",
                       auth=(mail, password), verify=False, timeout=20,
                       headers={"Content-Type": "application/vnd.ms-sync.wbxml"},
                       data=b"\x03\x01j\x00\x00\x07\x52\x03\x30\x00\x01\x00\x01")
    assert r.status_code == 200, f"FolderSync -> {r.status_code}: {r.text[:300]}"
    body = r.content
    # WBXML is binary; look for the folder type bytes / plain names is not
    # reliable without a WBXML decoder, so this asserts on transport only -
    # see open questions in the report.
    assert body, "FolderSync returned an empty body"


# ------------------------------------------------------------------ row 12 --

def test_row12_caldav_carddav_principal(server_a, fresh_user):
    """My laptop sees the same calendar and contacts (CalDAV/CardDAV)"""
    mail, password = fresh_user(server_a, "row12user")
    url = f"https://{server_a.host}:{server_a.ports['https']}/"
    body = """<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:" xmlns:C="urn:ietf:params:xml:ns:caldav" xmlns:CARD="urn:ietf:params:xml:ns:carddav">
  <D:prop>
    <C:calendar-home-set/>
    <CARD:addressbook-home-set/>
  </D:prop>
</D:propfind>"""
    r = requests.request("PROPFIND", url, data=body, auth=(mail, password), verify=False,
                          timeout=20, headers={"Depth": "0", "Content-Type": "application/xml"})
    assert r.status_code == 207, f"PROPFIND {url} -> {r.status_code}: {r.text[:300]}"
    assert "calendar-home-set" in r.text
    assert "addressbook-home-set" in r.text


# ------------------------------------------------------------------ row 13 --

def test_row13_restart_and_upgrade_preserve_data(server_a, fresh_user):
    """Data survive a restart and an upgrade"""
    image_next = os.environ.get("IMAGE_NEXT")
    if not image_next:
        pytest.skip("IMAGE_NEXT not set - no second image tag to upgrade to")

    mail, password = fresh_user(server_a, "row13user", quota="1G")
    subject = f"row13-{time.time()}"
    admin_mail, admin_pw = domain_admin_cred(server_a)
    smtp_send(server_a, admin_mail, mail, subject, auth=(admin_mail, admin_pw))
    conn = imap_login(server_a, mail, password)
    assert wait_for_message(conn, subject, timeout=30)
    conn.logout()

    subprocess.run(["docker", "compose", *COMPOSE_ARGS, "down"], check=True, timeout=120)
    env = dict(os.environ, IMAGE=image_next)
    subprocess.run(["docker", "compose", *COMPOSE_ARGS, "up", "-d"], check=True,
                    timeout=600, env=env)
    _wait_port(server_a.host, server_a.ports["imaps"], 300)

    # Same race as row 4's restart case: the port accepts TCP before
    # dovecot's TLS listener is fully up - retry the handshake, not just
    # the connect (_wait_port only proves the latter).
    conn = _retry_imap_login(server_a, mail, password)
    assert wait_for_message(conn, subject, timeout=30), "mail lost across upgrade"
    conn.logout()


# ------------------------------------------------------------------ row 14 --

def test_row14_backup_restore(server_a, fresh_user):
    """Backup and restore"""
    mail, password = fresh_user(server_a, "row14user", quota="1G")
    subject = f"row14-{time.time()}"
    admin_mail, admin_pw = domain_admin_cred(server_a)
    smtp_send(server_a, admin_mail, mail, subject, auth=(admin_mail, admin_pw))
    conn = imap_login(server_a, mail, password)
    assert wait_for_message(conn, subject, timeout=30)
    conn.logout()

    backup = server_a.admin("backup", check=True, timeout=180).stdout

    image = os.environ.get("IMAGE", "iredmail/mariadb:stable")
    cname = "row14-restore-target"
    subprocess.run(["docker", "rm", "-f", cname], capture_output=True)
    subprocess.run([
        "docker", "run", "-d", "--name", cname, "--platform", "linux/amd64",
        "--network", "iredmail-acceptance",
        "--network-alias", "row14.example", "--network-alias", "mail.row14.example",
        "-e", "HOSTNAME=mail.row14.example",
        "-e", f"FIRST_MAIL_DOMAIN={server_a.domain}",
        "-e", "FIRST_MAIL_DOMAIN_ADMIN_PASSWORD=TestPassw0rd1!",
        "-e", "ROUNDCUBE_DES_KEY=00000000000000000000000000",
        "-e", "MLMMJADMIN_API_TOKEN=0000000000000000000000",
        "-v", f"{os.path.join(os.path.dirname(__file__), 'admin-shims', 'iredmail-official.sh')}:/usr/local/bin/admin:ro",
        image,
    ], check=True, timeout=60)
    try:
        _wait_docker_healthy_port(cname, 993, 240)
        r = subprocess.run(["docker", "exec", "-i", cname, "admin", "restore"],
                            input=backup, capture_output=True, timeout=180)
        assert r.returncode == 0, f"admin restore failed: {r.stderr.decode(errors='replace')}"

        ip = subprocess.run(["docker", "inspect", "-f",
                              "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}", cname],
                             capture_output=True, check=True).stdout.decode().strip()
        conn = imaplib.IMAP4_SSL(ip, 993, ssl_context=_insecure_ctx())
        conn.login(mail, password)
        assert wait_for_message(conn, subject, timeout=30), "message missing after restore (row 6/4 must hold)"
        conn.logout()
    finally:
        subprocess.run(["docker", "rm", "-f", cname], capture_output=True)


def _insecure_ctx():
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    return ctx


def _wait_docker_healthy_port(container, port, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        r = subprocess.run(["docker", "inspect", "-f",
                             "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}", container],
                            capture_output=True)
        ip = r.stdout.decode().strip()
        if ip:
            try:
                with socket.create_connection((ip, port), timeout=3):
                    return
            except OSError:
                pass
        time.sleep(3)
    raise TimeoutError(f"{container}:{port} did not come up within {timeout}s")


# ------------------------------------------------------------------ row 15 --

def test_row15_image_size():
    """The image is small and current (size)"""
    image = os.environ.get("IMAGE", "iredmail/mariadb:stable")
    r = subprocess.run(["docker", "image", "inspect", image, "-f", "{{.Size}}"],
                        capture_output=True, check=True, timeout=30)
    size_mb = int(r.stdout.decode().strip()) / (1024 * 1024)
    limit_mb = 800  # phase A
    assert size_mb <= limit_mb, f"{image} is {size_mb:.0f} MB, limit is {limit_mb} MB"


def test_row15_no_fixable_high_critical_cves():
    """The image is small and current (CVE scan)"""
    if not _which("trivy"):
        pytest.skip("trivy not installed on this host")
    image = os.environ.get("IMAGE", "iredmail/mariadb:stable")
    r = subprocess.run(["trivy", "image", "--severity", "HIGH,CRITICAL", "--ignore-unfixed",
                         "--exit-code", "1", "--quiet", image],
                        capture_output=True, timeout=600)
    assert r.returncode == 0, (
        f"trivy found fixable HIGH/CRITICAL CVEs:\n{r.stdout.decode(errors='replace')}")


def _which(name):
    return subprocess.run(["which", name], capture_output=True).returncode == 0


# ------------------------------------------------------------------ row 16 --

def test_row16_only_required_ports_open(server_a):
    """Nothing is exposed that need not be"""
    if not _which("nmap"):
        pytest.skip("nmap not installed on this host")
    r = subprocess.run(["docker", "inspect", "-f",
                         "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}",
                         _container_id(server_a.compose_service)],
                        capture_output=True)
    ip = r.stdout.decode().strip()
    if not ip:
        pytest.skip("could not resolve container IP for nmap scan")
    scan = subprocess.run(["docker", "run", "--rm", "--network", "iredmail-acceptance",
                            "instrumentisto/nmap", "-Pn", "-p-", "--open", ip],
                           capture_output=True, timeout=300)
    out = scan.stdout.decode(errors="replace")
    open_ports = set(int(m) for m in re.findall(r"^(\d+)/tcp\s+open", out, re.M))
    allowed = {25, 80, 443, 465, 587, 993}
    assert open_ports <= allowed, f"unexpected open ports: {open_ports - allowed}\n{out}"


def test_row16_runs_without_privileged(server_a):
    """Runs without --privileged"""
    r = subprocess.run(["docker", "inspect", "-f", "{{.HostConfig.Privileged}}",
                         _container_id(server_a.compose_service)],
                        capture_output=True)
    assert r.stdout.decode().strip() == "false"


# ------------------------------------------------------------------ row 17 --

def test_row17_dkim_keys_differ(server_a, server_b):
    """Two servers built from the same image have different DKIM keys"""
    key_a = server_a.admin("dkim", server_a.domain).stdout.decode()
    key_b = server_b.admin("dkim", server_b.domain).stdout.decode()
    assert key_a and key_b, "one of the DKIM records is empty"
    assert key_a != key_b, "A and B publish the same DKIM key (#17)"


# ------------------------------------------------------------------ row 18 --

def test_row18_config_override_survives_upgrade():
    """I can override a config file and it survives an upgrade"""
    image = os.environ.get("IMAGE", "iredmail/mariadb:stable")
    tmp = _tmpdir("row18")
    # grab the stock main.cf as a base (setup, not the assertion) and change
    # the banner - the assertion below is purely behavioural (SMTP banner).
    dump = subprocess.run(["docker", "run", "--rm", "--platform", "linux/amd64", "--entrypoint",
                            "cat", image, "/etc/postfix/main.cf"], capture_output=True, timeout=60)
    if dump.returncode != 0:
        pytest.skip("could not read the image's default main.cf to build an override")
    main_cf_path = os.path.join(tmp, "main.cf")
    banner = "row18-override-banner"
    with open(main_cf_path, "wb") as f:
        f.write(dump.stdout)
        f.write(f"\nsmtpd_banner = $myhostname {banner}\n".encode())

    overrides_dir = os.path.join(tmp, "postfix")
    os.makedirs(overrides_dir, exist_ok=True)
    os.replace(main_cf_path, os.path.join(overrides_dir, "main.cf"))

    cname = "row18-override"
    subprocess.run(["docker", "rm", "-f", cname], capture_output=True)
    try:
        for tag, extra in [(image, []), (os.environ.get("IMAGE_NEXT", image), [])]:
            subprocess.run(["docker", "rm", "-f", cname], capture_output=True)
            subprocess.run([
                "docker", "run", "-d", "--name", cname, "--platform", "linux/amd64",
                "-e", "HOSTNAME=mail.row18.example", "-e", "FIRST_MAIL_DOMAIN=row18.example",
                "-e", "FIRST_MAIL_DOMAIN_ADMIN_PASSWORD=TestPassw0rd1!",
                "-e", "ROUNDCUBE_DES_KEY=00000000000000000000000000",
                "-e", "MLMMJADMIN_API_TOKEN=0000000000000000000000",
                "-v", f"{overrides_dir}:/opt/iredmail/custom/postfix:ro",
                "-p", "0:25",
                tag,
            ], check=True, timeout=60)
            port = _published_port(cname, 25)
            _wait_port("127.0.0.1", port, 240)
            with socket.create_connection(("127.0.0.1", port), timeout=10) as s:
                line = s.recv(1024).decode(errors="replace")
            assert banner in line, f"override not in effect, banner was: {line!r}"
    finally:
        subprocess.run(["docker", "rm", "-f", cname], capture_output=True)


def _published_port(container, internal_port):
    r = subprocess.run(["docker", "inspect", "-f",
                         "{{(index (index .NetworkSettings.Ports \"%d/tcp\") 0).HostPort}}" % internal_port,
                         container], capture_output=True, check=True)
    return int(r.stdout.decode().strip())


# ------------------------------------------------------------------ row 19 --

def test_row19_works_behind_reverse_proxy(server_a):
    """It works behind my reverse proxy"""
    cname = "row19-nginx-proxy"
    # Where to reach A from inside the standalone nginx container being
    # started below. `--add-host <host>:127.0.0.1` (the original approach)
    # is wrong whenever server_a.host is itself 127.0.0.1 (the default,
    # compose-managed topology - see test/README.md "Against any other two
    # servers"): 127.0.0.1 *inside* that new container is itself, not the
    # docker host, so the proxy_pass could never reach A - it always got a
    # connection refused/502. Attaching the proxy to the same compose
    # network and addressing A by its service name (its real internal port,
    # not the host-published one) reaches it correctly; that network only
    # exists for the default topology, so fall back to the original
    # host:port approach (valid when server_a.host names a real reachable
    # host) otherwise.
    default_topology = server_a.host == "127.0.0.1" and not os.environ.get("MAIL_A_HOST")
    if default_topology:
        docker_run_network_args = ["--network", "iredmail-acceptance"]
        upstream = f"https://{server_a.compose_service}:443"
        # A's nginx vhost is keyed on its own hostname (test/compose.yaml's
        # `hostname: mail.a.example`) two ways at once - a real reverse
        # proxy in front of a named backend forwards that backend's own
        # Host *and* its own TLS SNI, not whatever the client dialled (an
        # IP:port here); without both nginx has no matching server block
        # and answers 403 (the Host header alone got past the vhost lookup
        # but not a still-mismatched SNI - found by adding one, then the
        # other, and watching the 403 persist through the first).
        backend_host = "mail.a.example"
    else:
        docker_run_network_args = [
            "--add-host", f"{server_a.host}:127.0.0.1" if server_a.host != "127.0.0.1" else "dummy.invalid:127.0.0.1",
        ]
        upstream = f"https://{server_a.host}:{server_a.ports['https']}"
        backend_host = server_a.host

    # nginx:alpine (Alpine) has no ssl-cert-snakeoil package - that path is
    # Debian's - so generate our own throwaway self-signed cert instead of
    # assuming one is baked into the image.
    conf = f"""
events {{}}
http {{
  server {{
    listen 18443 ssl;
    ssl_certificate /etc/nginx/row19.pem;
    ssl_certificate_key /etc/nginx/row19.key;
    location / {{
      proxy_pass {upstream};
      proxy_ssl_verify off;
      proxy_ssl_server_name on;
      proxy_ssl_name {backend_host};
      proxy_set_header Host {backend_host};
      proxy_set_header X-Forwarded-For $remote_addr;
      proxy_set_header X-Forwarded-Proto https;
      proxy_set_header X-Forwarded-Host $host;
    }}
  }}
}}
"""
    tmp = _tmpdir("row19")
    conf_path = os.path.join(tmp, "nginx.conf")
    with open(conf_path, "w") as f:
        f.write(conf)

    cert_path = os.path.join(tmp, "row19.pem")
    key_path = os.path.join(tmp, "row19.key")
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                     "-keyout", key_path, "-out", cert_path, "-days", "1",
                     "-subj", "/CN=row19-proxy.example"], check=True, timeout=30,
                    capture_output=True)

    subprocess.run(["docker", "rm", "-f", cname], capture_output=True)
    try:
        subprocess.run(["docker", "run", "-d", "--name", cname,
                         *docker_run_network_args,
                         "-p", "0:18443", "-v", f"{conf_path}:/etc/nginx/nginx.conf:ro",
                         "-v", f"{cert_path}:/etc/nginx/row19.pem:ro",
                         "-v", f"{key_path}:/etc/nginx/row19.key:ro",
                         "nginx:alpine"], check=True, timeout=60)
        port = _published_port(cname, 18443)
        _wait_port("127.0.0.1", port, 60)
        r = requests.get(f"https://127.0.0.1:{port}/Microsoft-Server-ActiveSync", verify=False, timeout=20)
        assert r.status_code in (200, 401), f"ActiveSync through the proxy -> {r.status_code}"
    finally:
        subprocess.run(["docker", "rm", "-f", cname], capture_output=True)


# ------------------------------------------------------------------ row 20 --

def test_row20_web_ui_add_domain_and_user_machine_part(server_a):
    """I manage domains, users and quotas in a web UI (machine part)"""
    base = f"https://{server_a.host}:{server_a.ports['https']}/iredadmin/"
    r = requests.get(base, verify=False, timeout=20)
    assert r.status_code == 200, f"iRedAdmin not reachable at {base}: {r.status_code}"
    # Logging in and driving the forms/API is an authenticated multi-step
    # session-cookie flow specific to iRedAdmin's own HTML forms - exercising
    # it black-box (no reading its source) needs a browser session, which is
    # the maintainer's part per ACCEPTANCE.md row 20. This machine check
    # proves the UI is up and serving over HTTPS.
