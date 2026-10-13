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

| Extension | Question it answers | State on 2026-10-12 |
|---|---|---|
| [`pg_lock_tree`](https://github.com/apjapj/pg_lock_tree) | what's stuck now | Shipping. 1.1.16 on main, tagged `v1.1.15` and `v1.1.16`, both released and 1.1.16 latest; 517 pgTAP tests green on PG 14 to 19beta4 on both CI systems |
| [`pg_bloat_cause`](https://github.com/apjapj/pg_bloat_cause) | what's slowing down | 0.1 built, current state only; tagged `v0.1.0` (release 0.1.0); 11 scenarios and 19 pgTAP tests green on 14 and 18 |
| [`pg_limit_runway`](https://github.com/apjapj/pg_limit_runway) | what will break next | 0.2.1 built, with history and projected dates; tagged `v0.2.0` and `v0.2.1` (releases 0.2.0 and 0.2.1); 19 scenarios and 71 pgTAP tests green on 14 and 18 |

The three extensions are separate repositories on purpose: install only what you need.
Changing the contract or the plan, and what this repository's gate does not check:
[CONTRIBUTING.md](CONTRIBUTING.md).

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
2. **Partly resolved on 2026-10-12.** ~~`event` values are not yet shared.~~ The vocabulary is now
   fixed in [ALERTS.md](ALERTS.md) (`alerting`, `escalated`, `cleared`). `pg_lock_tree` sends
   `alerting` and `cleared`; the remaining gap is that it does not yet send `escalated`, proposed for
   1.2.0. Open only for `escalated`.
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
- **The `event` vocabulary**: `alerting` (onset), `escalated`, `cleared`. pg_lock_tree currently
  sends `alerting` for both onset and escalation; decide whether `escalated` is added there or
  whether the umbrella adopts pg_lock_tree's two values as-is.
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

### 3. Fix the shared conventions

Short, and written once here so the new tools do not each reinvent them:

- **Naming**: every object prefixed with the tool name (`lock_tree_*`, `bloat_cause_*`,
  `limit_runway_*`), as pg_lock_tree already does.
- **Function shapes**: the same verbs across tools, so muscle memory transfers. `_text()` for
  reading, `_command()` for runnable SQL that never runs itself, `_sample()`, `_notify()`,
  `_notify_resolved()`, `_prune()`, `_history_size()`, and `_find()` for a search over sampled
  history that reads the stored tier and nothing else. `_find()` is in that list because
  `pg_lock_tree` shipped `lock_tree_archive_find()` before this document existed, and renaming a
  released function to match a convention learned afterwards would break callers for no gain.
- **Settings namespace**: `<tool>.<setting>` GUCs, as `lock_tree.actions` and
  `lock_tree.history_query` do.
- **Redaction**: any tool storing query text reuses pg_lock_tree's rules (redact by default,
  `SCRAM-SHA-256$4096:<salt>$<StoredKey>:<ServerKey>` shape included). pg_bloat_cause will store the
  text of long transactions holding back VACUUM, so this applies to it.
- **Optional dependencies**: a tool may use another if it is installed (pg_bloat_cause calling
  pg_lock_tree for the lock chain) but must work without it, find it through `pg_extension` rather
  than assuming a schema, and its tests must pass with and without it.
- **Docs layout**: the README, INSTALL, docs/incident, docs/alerting, docs/history, docs/reference,
  docs/roadmap, CHANGELOG split that pg_lock_tree uses.

### 4. Share the test matrix

pg_lock_tree's `scripts/matrix.sh` and Docker images already run PG 14 to 19. Extract the image and
runner so all three tools run the same matrix, plus one job that installs all three into one
database and runs every suite, which is the only test of "works alongside".

### 5. Add `tool` to pg_lock_tree (in that project, not here)

Once step 1 is written: a minor pg_lock_tree release adding `tool: "pg_lock_tree"` and any other
required keys to both payloads, with a test that the payload validates against the contract. Raise
it on pg_lock_tree's roadmap.

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

The checklist is in pg_lock_tree's [docs/roadmap.md](https://github.com/apjapj/pg_lock_tree/blob/main/docs/roadmap.md#making-the-repository-public),
where its roadmap lives: what can be prepared now (internal host names in the workflows and history,
secret scanning on GitHub, a licence GitHub can detect, a security policy, release notes) and the
outward steps that are Piotr's alone (pushing the public tags, the GitHub Releases, visibility, branch
protection). As of 2026-10-12 the public tags are v1.1.15 and v1.1.16 (both released); what remains for
Piotr alone is visibility and branch protection. This page goes public with or after pg_lock_tree,
so the links above are live for a public reader when it does.

## Open questions

- One repository or three? Today each tool is its own directory. A monorepo makes the shared matrix
  and contract easy; three repos keep "install only what you need" literal. Recommendation: three
  repos plus this directory as the umbrella, since pg_lock_tree is already standalone.
- Should there be a meta-extension (`CREATE EXTENSION pg_incident_watch CASCADE`) that requires all
  three? Cheap to add, but it contradicts "install only what you need" as the headline. Recommend not
  until someone asks.
- Does the umbrella ever offer a single "what's wrong right now" view across installed tools? It
  would be the obvious first query in an incident, and it is also how this becomes a dashboard.
