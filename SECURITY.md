# Security policy

## Supported versions

This repository has no extension and no releases: the current text and `scripts/listen.sh` on `main`
are the only supported version, and there is nothing to upgrade from. Each extension's own policy
says which of its versions are supported.

`scripts/listen.sh` runs under the role you connect as and does exactly what `psql` does. It opens no
port, listens on nothing, and sends nothing anywhere: it prints what the database sends it. If you
add a forwarding option to it, that changes this paragraph, because a script that can page is a
different thing from one that cannot.

## Reporting a vulnerability

**Do not open a public issue.** There are two ways to report privately, and either is fine.

**By e-mail: linux.postgres+pg_incident_watch@gmail.com.** This works today, and it keeps working: the
address does not depend on anything about this repository.

**By GitHub:** the **Report a vulnerability** button, on this repository's Security tab, under
Advisories. A report there is a private advisory that only you and the maintainers can see, and you
are credited on it. GitHub offers this on public repositories only, so it appears here once this
repository is public; the e-mail above is the channel that works either way.

Either way, please include which of the family's extensions and documents it concerns, their
versions, the PostgreSQL major version, the roles and grants involved, and the smallest reproduction.

You will get an acknowledgement within 7 days. This is a small project maintained in spare time, so
there is no fixed date for a fix; you will be told what is planned, and credited by name in the
commit that carries the fix unless you ask not to be.

This repository is never tagged and has no CHANGELOG, deliberately: it ships no extension, so
there is nothing to version. Its history is the record, and `git log` is the place to look. The
three extensions each keep a CHANGELOG and credit reporters there.

## What counts

This repository holds the family's shared contract and plan, and one reference listener. A
vulnerability in an extension belongs to that extension's repository and its own policy:
[pg_lock_tree](https://github.com/apjapj/pg_lock_tree), [pg_bloat_cause](https://github.com/apjapj/pg_bloat_cause)
and [pg_limit_runway](https://github.com/apjapj/pg_limit_runway). Report it here when it is in what
is shared: the alert contract (ALERTS.md), for example a payload key that would carry something a
listener should not receive, or a problem that only appears with the extensions installed together.
If you are not sure which repository it belongs to, report it here.
