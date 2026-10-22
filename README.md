# pg_incident_watch

[![Contract check](https://github.com/apjapj/pg_incident_watch/actions/workflows/ci.yml/badge.svg)](https://github.com/apjapj/pg_incident_watch/actions/workflows/ci.yml)
[![Licence: PostgreSQL](https://img.shields.io/badge/licence-PostgreSQL-blue.svg)](LICENSE)

**Detect, diagnose and act on PostgreSQL incidents from inside the database.**

Umbrella for three small, independent, pure-SQL extensions. This repository holds the family's
shared contract and plan, plus the one piece of code that belongs to the family rather than to
any one tool: [`scripts/listen.sh`](scripts/listen.sh), a reference listener that follows all
three tools at once. The planning document this was drafted from is not public; what is, and what
the tools are held to, is this page and [ALERTS.md](ALERTS.md).

This repository is <https://github.com/apjapj/pg_incident_watch>. It is one of four: this
umbrella and the three extensions it covers.

| Extension | Question it answers | State on 2026-10-20 |
|---|---|---|
| [`pg_lock_tree`](https://github.com/apjapj/pg_lock_tree) | what's stuck now | 1.2.0 on main, tagged `v1.2.0` and released; 538 pgTAP tests green on PG 14 to 19rc1 on both CI systems |
| [`pg_bloat_cause`](https://github.com/apjapj/pg_bloat_cause) | what's slowing down | 0.5.0 on main, adding the `bloat_cause.holder_query` opt-in; `v0.4.1` is the newest tag and `v0.5.0` awaits its cut; 15 scenarios and 152 pgTAP tests green on PG 14 to 19 |
| [`pg_limit_runway`](https://github.com/apjapj/pg_limit_runway) | what will break next | 0.5.1 on main, tagged `v0.5.1` and released, fixing the schema-USAGE bug the family stack found; 19 scenarios and 150 pgTAP tests green on PG 14 to 19 |

The three extensions are separate repositories on purpose: install only what you need.
Changing the contract or the plan, and what this repository's gate does not check:
[CONTRIBUTING.md](CONTRIBUTING.md).

## Start here

New to the family? The [first five minutes](docs/first-five-minutes.md) gets you to the three first
queries. If you are already in an incident, [Which tool first](docs/which-tool-first.md) is the
paper decision tree.


New to the family? [The first five minutes](docs/first-five-minutes.md) takes you from install to
the three first queries, the grants that are easy to miss, and the one-row-at-a-time action rule.

## Overview

Most PostgreSQL outages have a known cause and a known diagnostic query: a session idle in a
transaction at the head of a lock queue, a forgotten replication slot holding back VACUUM, an `int4`
key or the XID counter running out on a predictable date. pg_incident_watch turns those queries into
tools that live in the database.

### What every tool promises

Each extension is pure SQL, installs with `CREATE EXTENSION`, needs no restart and no
`shared_preload_libraries`, runs on PostgreSQL 14 and later, and works on its own.

| Stage | What every tool provides |
|---|---|
| **Detect** | Quiet `NOTIFY` alerting: once when a problem starts, again only when it gets materially worse, and once when it clears |
| **Diagnose** | A ranked answer, worst first, in plain columns and readable text |
| **Act** | The least destructive statement that will fix it, ready to paste or run with `\gexec` |
| **Review** | Sampled history, so an incident can be examined after it has ended |

Alerts from all three share one JSON payload format with a `tool` field, so one listener can route
all of them. [`scripts/listen.sh`](scripts/listen.sh) is that listener, and it is the one piece of
code this repository owns:

```bash
PGHOST=... PGDATABASE=... ./scripts/listen.sh
```

It opens three `LISTEN`s in one session and prints each payload as it arrives, routed on `tool`.
It needs only `psql`, takes its connection from the standard libpq environment variables, and
checks each payload against the required-key table in [ALERTS.md](ALERTS.md) as it goes, so a
payload that has lost a key is visible at the moment it arrives. Two things it deliberately does
not do, per rule 1: it never treats an unrecognised key as a defect, and it never sends anything
anywhere. Paging is the deployment's decision, not this script's.

The contract check verifies the listener against `ALERTS.md` rather than against a copy, so the two
cannot drift: if rule 3 names a channel the listener does not open, or the required-key table grows
a row the listener does not check, `make`-equivalent CI fails with the file and the line.

### What it is not

Not a dashboard and not a pager. It does not replace pgwatch, Prometheus or pganalyze, and it does
not page anyone. It knows what is wrong and says so on a channel; wiring that channel to a pager is
the rota's decision. pgwatch can graph the views these tools expose; pgFirstAid is a broader,
shallower single-function health check. Both are complementary.

### Install, as the overview describes it

```sql
CREATE EXTENSION pg_lock_tree;      -- any one, or all three
CREATE EXTENSION pg_bloat_cause;
CREATE EXTENSION pg_limit_runway;
```

A monitoring role needs `pg_read_all_stats` plus `SELECT` on each tool's views; see each tool's
`INSTALL.md`. History and alerting are opt-in: schedule the sample functions with `pg_cron` or a host
cron job.

## Where the overview and pg_lock_tree disagree

A dated audit, first run on 2026-10-08 and re-checked on 2026-10-12. These are the gaps between what
the umbrella promises and what the one shipping tool does. Each item carries its status: **Open** means
it still holds, **Resolved** means it no longer does. pg_lock_tree is not changed by this document.

1. **Resolved on 2026-10-12.** ~~There is no `tool` field yet.~~ `pg_lock_tree` has emitted `tool`,
   `subject` and `sampled_at` since 1.1.11, under its additive-keys rule. Nothing is outstanding.
2. **Resolved.** ~~`event` values are not yet shared.~~ The family uses two values, `alerting` and
   `cleared`, fixed in [ALERTS.md](ALERTS.md). Escalation is carried by two payload fields, `level`
   and `previous_level`, on the `alerting` event, not a third event value; `pg_lock_tree` sends them
   in 1.2.0. `escalated` stays in the vocabulary (rule 2) and is sent by no tool.
3. **Open.** **"PostgreSQL 14 and later" outlives PG 14's support.** PG 14 reaches end of life on
   2026-11-12 (`pg_lock_tree/CONTRIBUTING.md`, "The matrix"). Decided on 2026-10-09: all three tools
   keep 14 as their floor anyway, so they stay useful to PG 14 users for months after that date. See
   next step 2.
4. **Open.** **"Installs with `CREATE EXTENSION`" needs the files on the server first.**
   `pg_lock_tree` is `trusted = false` and installs via `make install`; RDS and Aurora are explicitly
   not promised (`docs/reference.md`, "Also not a promise"). The overview should say so in the same
   paragraph.
5. **Resolved on 2026-10-12.** ~~"See each tool's INSTALL.md" is only true for pg_lock_tree.~~ All
   three tools now ship an INSTALL.md.

## Next steps

In order. The first three are decisions the other two tools are blocked on; the rest can run in
parallel with their builds.

### 1. Write the shared alert contract ~~(`ALERTS.md` in this directory)~~ **Done**

The one thing that makes three extensions a family rather than three repos. Decide and write down:

- **Required keys**, present in every payload from every tool: `tool`, `channel`, `event`, `subject`
  (what the alert is about, stable across samples: a root's `application_name`, a table's
  qualified name, a limit's identity), `summary` (one human sentence), and `sampled_at`.
- **The `event` vocabulary**: two values, `alerting` and `cleared`. Escalation is not a third event;
  it is the payload fields `level` and `previous_level` on an `alerting`, so a consumer tells an onset
  from an escalation without a new event name.
- **Tool-specific keys** stay allowed and stay additive-only, under pg_lock_tree's existing rule that
  a consumer must ignore keys it does not recognise.
- **Channels**: one per tool (`lock_tree`, `bloat_cause`, `limit_runway`) as today, or one shared
  `incident_watch` channel. Recommendation: keep one per tool, default name equal to `tool`, so a
  listener can `LISTEN` to exactly what it routes and pg_lock_tree needs no channel change.
- **Size**: stay well under the 8000-byte NOTIFY limit; no unbounded arrays in payloads.
- **De-duplication rules**: onset once, escalate on a materially-worse edge compared against the
  value at the last notification (not the last sample), clear once. This is pg_lock_tree's
  `lock_tree_alert` design (`docs/alerting.md`) written as the family rule, so each tool defines
  only what "materially worse" means for it.

### 2. ~~Decide the version floor~~ **Done**

Decided on 2026-10-09: **PostgreSQL 14 and later**, for all three tools, so they stay useful to PG 14 users past
its end of life. PostgreSQL 14 reaches upstream end of life on 2026-11-12, and the floor is revisited then.

Anything newer than 14 is a per-feature check that degrades with a stated message, never a floor.
For example `pg_stat_user_tables.n_tup_newpage_upd` exists only on 16 and later, so on 14 and 15
pg_bloat_cause's HOT-update finding cannot use it and must say so in the finding rather than guess.

### 3. ~~Fix the shared conventions~~ **Done: [CONTRIBUTING.md](CONTRIBUTING.md#shared-conventions)**

The conventions are written once, there, and the three tools follow them.

### 4. ~~Share the test matrix~~ **Done: the family stack**

`stacks/family.toml` is the first concrete stack: the three extensions, their pinned refs, the
`postgres` database (pg_cron can only be created there), and the cross-tool contract.
`scripts/coexist.sh` installs them into one database, runs every suite, and asserts that each
sender carries `level` and `previous_level` on `alerting` with its own default channel.

The first run found a real defect: `limit_runway_sequences()` required `SELECT` on a sequence but
not `USAGE` on its schema, so `cron.jobid_seq` raised instead of being marked unreadable. Fixed in
0.5.1. The stack runs on 14-18 now; 19 joins at GA, though the three tools' own CI already runs
19rc1. The book's stacks work (plan item 4.6) should adopt this manifest format rather than
invent a second one.

### 5. ~~Add `tool` to pg_lock_tree~~ **Done: pg_lock_tree 1.1.11**

`pg_lock_tree` 1.1.11 added `tool`, `subject` and `sampled_at` to both payloads, with the payload
validated against the contract by its alert test in `pg_lock_tree`.

### 6. ~~Ship a reference listener~~ **Done: [`scripts/listen.sh`](scripts/listen.sh)**

`LISTEN`s on all three channels in one session and prints the payloads, routing on `tool`. A `psql`
loop rather than `listen.py`, for one reason: `psql` ships with every PostgreSQL installation, so
this runs anywhere without a driver. It proves the shared format works and is the thing a rota
copies. It stays an example, not a component: paging is still the deployment's job, and the script
opens no port and sends nothing anywhere.

The obvious way to write this does not work, which is worth recording because the failure is silent.
psql's `NOTIFY_PAYLOAD` variable is the documented way to read a notification's payload, and psql
populates it only when it is reading commands from a terminal. In a script it stays unset, the
listener runs, connects, and prints nothing at all, with no error anywhere. Verified on 18.6 both
with `-f` and on stdin. In a script psql instead prints its own message, and the script slices the
payload between two fixed literals in it. For a long-running listener, `psycopg2` blocks on the
socket and has no polling interval at all; that variant is not shipped because it needs a driver.

### 7. Release the overview

Update this page and the PDF once 1 to 3 are decided: correct the version line, add the
`make install` caveat, and link each tool's INSTALL.md as they appear.

### 8. Make the family public, starting with pg_lock_tree

The repositories are public, the current releases are tagged and released (`v1.2.0`, `v0.4.1`,
`v0.5.1`), with `v0.5.0` on `pg_bloat_cause`'s main awaiting its tag, and `main` is protected by a
pull-request rule on both GitHub and Forgejo. The `SECURITY.md` files point at GitHub's private
vulnerability reporting, which is enabled on all four.

## Decisions

The eleven scope questions carried across the tools are answered in
[docs/scope-decisions.md](docs/scope-decisions.md): what `pg_bloat_cause` will and will not measure,
how `pg_limit_runway` reads its limits, and what the umbrella will never become.

