# Security policy

## Supported versions

This repository has no code and no releases: the current text on `main` is the one supported.
Each extension's own policy says which of its versions are supported.

## Reporting a vulnerability

**Do not open a public issue.** Report it privately with GitHub's **Report a vulnerability** button,
on this repository's Security tab, under Advisories. The report is a private advisory that only you
and the maintainers can see, and you are credited on it.

If you cannot use GitHub, e-mail **linux.postgres+pg_incident_watch@gmail.com** instead.

Either way, please include which of the family's extensions and documents it concerns, their
versions, the PostgreSQL major version, the roles and grants involved, and the smallest reproduction.

You will get an acknowledgement within 7 days. This is a small project maintained in spare time, so
there is no fixed date for a fix; you will be told what is planned, and credited in the CHANGELOG
unless you ask not to be.

## What counts

This repository holds the family's shared contract and plan, not code. A vulnerability in one of the
extensions belongs to that extension's repository and its own policy:
[pg_lock_tree](https://github.com/apjapj/pg_lock_tree), [pg_bloat_cause](https://github.com/apjapj/pg_bloat_cause)
and [pg_limit_runway](https://github.com/apjapj/pg_limit_runway). Report it here when it is in what
is shared: the alert contract (ALERTS.md), for example a payload key that would carry something a
listener should not receive, or a problem that only appears with the extensions installed together.
If you are not sure which repository it belongs to, report it here.
