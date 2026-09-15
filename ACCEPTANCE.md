# Acceptance table

What this project must do, in the words of the person running it. Every row is
a behaviour observable from outside the container through a public interface
(SMTP, IMAP, HTTPS, ActiveSync, CalDAV/CardDAV, the `admin` command), from a
fresh `docker compose up`, with nothing planted by hand. **Tests are these
rows, one to one, and must not depend on what is inside the container** - the
same suite has to pass against the iRedMail-based image (phase A) and against
a hand-composed minimal stack (phase B). A test that reads a config file, runs
`doveadm`, or greps a log for an implementation detail is wrong.

Agreed with the maintainer on 2026-09-15. A row is changed only by a message
to him.

| # | Behaviour | Observed how | Expected | Checked by |
|---|---|---|---|---|
| 1 | The server starts from nothing and is healthy | `docker compose up -d`, wait for healthcheck | every service `healthy` within 120 s; no line matching `error` in the startup log | machine |
| 2 | I add a domain | `admin domain add example.org` | exit 0; `admin domain list` shows it; the MX and DKIM DNS records to publish are printed | machine |
| 3 | I remove a domain | `admin domain rm example.org` | its users and mail are gone, other domains untouched (data-directory delta) | machine |
| 4 | I add / remove a user with a password and a quota | `admin user add alice@example.org --password … --quota 1G`, then `admin user rm` | exit 0; IMAP login for alice succeeds; after `rm` login is refused; a container restart does **not** change the password (#47) | machine |
| 5 | I change a quota; exceeding it refuses delivery | `admin user quota alice@example.org 1M`; send a 2 MB message | IMAP `GETQUOTA` reports 1M; the sender gets `552`/a bounce, never silent loss | machine |
| 6 | A user sends mail to another server and it arrives | two servers side by side (A, B): authenticated submission on A:587 with STARTTLS to bob@b.example | within 30 s the message is in Bob's INBOX on B via IMAP, carrying `DKIM-Signature` from A and `Authentication-Results: … dkim=pass` added by B | machine |
| 7 | The reply arrives back | B → A | message in Alice's INBOX on A | machine |
| 8 | Nobody can send through the server without logging in | unauthenticated SMTP on :25 with a foreign sender to a foreign recipient | `554 5.7.1 … Relay access denied` | machine |
| 9 | Spam and viruses do not reach the INBOX | GTUBE and EICAR from B to A | GTUBE lands in Junk or is rejected; EICAR is rejected with `5xx` | machine |
| 10 | Mail is encrypted in transit | `openssl s_client -starttls smtp`, `imaps`, `https` | TLS 1.2+, certificate for the configured hostname (self-signed with exact CN in tests; mounted real certs in production) | machine |
| 11 | My phone has mail, calendar and contacts with push, via one Exchange account | ActiveSync: `OPTIONS /Microsoft-Server-ActiveSync`, then `FolderSync` with auth | 200, `MS-ASProtocolVersions` contains `14.1`; `FolderSync` returns Inbox, Calendar, Contacts folders | machine + maintainer (adds the account on an iPhone; a new mail pushes) |
| 12 | My laptop sees the same calendar and contacts (CalDAV/CardDAV) | `PROPFIND` on the principal URL with auth | 207 with `calendar-home-set` and `addressbook-home-set`; an event created via CalDAV is visible via ActiveSync and vice versa | machine |
| 13 | Data survive a restart and an upgrade | `docker compose down` (no `-v`), new image tag, `up` | Alice's mail, the users and the quotas are unchanged; no manual step; a mis-mounted volume is refused at startup instead of silently using an anonymous one (#84) | machine |
| 14 | Backup and restore | `admin backup > f`; fresh server; `admin restore < f` | rows 4 and 6 hold on the restored server | machine |
| 15 | The image is small and current | `docker image inspect`, `apt list --upgradable`, Trivy | size ≤ 800 MB (phase A) / ≤ 400 MB (phase B); zero HIGH/CRITICAL CVEs with a fix available | machine (CI, weekly) |
| 16 | Nothing is exposed that need not be | port scan of the container; capabilities | only 25, 465, 587, 993, 443 (+80 for ACME) open; runs without `--privileged` | machine |
| 17 | Two servers built from the same image have different DKIM keys | compare the DKIM DNS record printed by A and by B | different public keys (#17) | machine |
| 18 | I can override a config file and it survives an upgrade | drop a file into the `overrides/` volume; restart; upgrade | the override is in effect (observable behaviour, e.g. a Postfix banner string), before and after the upgrade | machine |
| 19 | It works behind my reverse proxy | nginx-proxy in front with `X-Forwarded-*` | HTTPS web (if any) and ActiveSync work through the proxy | machine |

Out of scope: LDAP, webmail as a requirement, OAuth2, Kubernetes, arm64 in phase A.
