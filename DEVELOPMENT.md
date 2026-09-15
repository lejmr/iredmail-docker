# Development

Being written during the 2026 refresh; sections are filled as the pieces land.

## Run it

    docker compose -f test/compose.yaml up -d --build   # servers A and B
    bin/test.sh                                         # the acceptance suite

## Tests

`test/` holds the acceptance suite: one test per row of `ACCEPTANCE.md`,
named after the row, written against public interfaces only (see
`CLAUDE.md`). `pytest` with plain `smtplib`/`imaplib`/`requests`; `swaks`
and `openssl s_client` where a raw conversation is clearer. The suite takes
`MAIL_A`/`MAIL_B` host:port settings so it can run against any two servers -
this image, the official `iredmail/mariadb` image, or the phase-B stack.

## Verifying a change

Every change is proven from a fresh `compose up` on the integration commit,
never from a running instance somebody has been poking at. Anything touching
the web/ActiveSync surface is also exercised with a real client by the
maintainer (batch), after the machine rows are green.
