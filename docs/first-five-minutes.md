# The first five minutes

You have just installed one or more of the family. This is the shortest path from "installed" to
"it found something and I know what to do next". It is not a replacement for INSTALL.md or the
individual reference pages.

## Minute 1: install what you need

```sql
CREATE EXTENSION pg_lock_tree;      -- what is stuck now
CREATE EXTENSION pg_bloat_cause;    -- what is slowing down
CREATE EXTENSION pg_limit_runway;   -- what will break next
```

Any one is useful on its own. They do not depend on each other, and the umbrella tests all three
together.

## Minute 2: give the reader the grants

A monitoring role needs `pg_read_all_stats` plus `SELECT` on the views it should read. That second
grant is easy to miss: `pg_read_all_stats` alone still hides other users' rows from these views.
Each extension's INSTALL.md has the exact statements.

## Minute 3: run the three first queries

The same queries are in [`scripts/first-five-minutes.sql`](../scripts/first-five-minutes.sql), which
skips a tool that is not installed rather than failing. Run it with `psql -X -f scripts/first-five-minutes.sql`.

```sql
-- Who is blocking whom, in plain text?
SELECT * FROM lock_tree_text();

-- Why are dead rows not being removed, worst table first?
SELECT relname, dead_rows, dead_pct, cause, cause_detail FROM bloat_cause LIMIT 10;

-- What limit is closest, and when does it arrive?
SELECT kind, object, until_date, state, detail FROM limit_runway LIMIT 10;
```

Each returns nothing serious on a quiet database. Empty is a valid answer; it is not an install
failure.

## Minute 4: act on one row, not all of them

`lock_tree_command()` and `bloat_cause_command()` return statements, not run them. Read the row,
then run the one you chose. Do not add `\gexec` to those queries: it would run every row, including
the ones you did not read.

`limit_runway_command()` returns the least destructive statement for a limit. For an expiring
sequence or an XID horizon, it is the one to schedule, not to paste blind on a busy primary.

## Minute 5: make it run without you

History and alerts need a scheduler. In the database, the usual shape is pg_cron:

```sql
SELECT cron.schedule('lock-tree-sample', '10 seconds', $$SELECT lock_tree_sample()$$);
SELECT cron.schedule('bloat-cause-sample', '1 hour', $$SELECT bloat_cause_sample()$$);
SELECT cron.schedule('limit-runway-sample', '1 hour', $$SELECT limit_runway_sample()$$);
SELECT cron.schedule('lock-tree-alert', '1 minute', $$SELECT lock_tree_notify()$$);
```

That is an example, not a required schedule. The samplers and senders take their thresholds as
arguments and do nothing until you call them. The family's reference listener, `scripts/listen.sh`,
shows how one session can listen on all three channels.

## If it is not working

- The view is empty on a busy server: check the grants in minute 2, especially `pg_read_all_stats`.
- `CREATE EXTENSION` cannot find the control file: the extension was not installed on the server's
  filesystem. See INSTALL.md; this is not a SQL-only install on a managed instance.
- A query returns "not established": the role cannot read the statistic or the relation, or the
  server has no history yet. Each tool names the reason rather than guessing.

## Where to go next

- Mid-incident: [the lock tree incident card](https://github.com/apjapj/pg_lock_tree#the-incident-card).
- Alerting: each extension's `docs/alerting.md` and the family [ALERTS.md](../ALERTS.md).
- After the incident: `pg_lock_tree/docs/after-the-incident.md`, `pg_bloat_cause/docs/detect.md`,
  `pg_limit_runway/docs/history.md`.
