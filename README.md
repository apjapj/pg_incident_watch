# pg_incident_watch

**Detect, diagnose and act on PostgreSQL incidents from inside the database.**

Umbrella for three small, independent, pure-SQL extensions. This directory holds the family's shared
contract and plan, not code. Source: `pg_incident_watch-overview.md.pdf`, Draft v0.1, 2026-10-08.

This repository is <https://github.com/apjapj/pg_incident_watch>. It is one of four: this
umbrella and the three extensions it covers.

| Extension | Question it answers | State on 2026-10-09 |
|---|---|---|
| [`pg_lock_tree`](https://github.com/apjapj/pg_lock_tree) | what's stuck now | Shipping. v1.1.13 released, green on PG 14 to 19beta4 |
| [`pg_bloat_cause`](https://github.com/apjapj/pg_bloat_cause) | what's slowing down | Design only. Overview and next steps written |
| [`pg_limit_runway`](https://github.com/apjapj/pg_limit_runway) | what will break next | Design only. Overview and next steps written |

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
all of them.

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

## Where the overview and pg_lock_tree disagree today

Checked against `../pg_lock_tree` on 2026-10-08. These are the gaps between what the umbrella
promises and what the one shipping tool does. pg_lock_tree is not changed by this document.

1. **There is no `tool` field yet.** pg_lock_tree's payload (`docs/alerting.md#the-payload`) is
   `channel`, `event`, `root_pid`, `application_name`, `blocked_sessions`, `max_depth`,
   `longest_wait`, `waiting_for`. Its stability rule ("NOTIFY payload keys: additive only",
   `docs/reference.md`) allows adding `tool`, so this is a minor release, not a break.
2. **`event` values are not yet shared.** pg_lock_tree emits `alerting` and `cleared`. The umbrella
   needs a fixed vocabulary every tool uses.
3. **"PostgreSQL 14 and later" outlives PG 14's support.** PG 14 reaches end of life on 2026-11-12
   (`pg_lock_tree/CONTRIBUTING.md`, "The matrix"). Decided on 2026-10-09: all three tools keep 14 as
   their floor anyway, so they stay useful to PG 14 users for months after that date. See next
   step 2.
4. **"Installs with `CREATE EXTENSION`" needs the files on the server first.** pg_lock_tree is
   `trusted = false` and installs via `make install`; RDS and Aurora are explicitly not promised
   (`docs/reference.md`, "Also not a promise"). The overview should say so in the same paragraph.
5. **"See each tool's INSTALL.md"** is only true for pg_lock_tree.

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

### 2. Decide the version floor

Decided: **PostgreSQL 14 and later**, for all three tools, so they stay useful to PG 14 users past
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

### 6. Ship a reference listener

A small script (`listen.py` or a `psql` loop) that `LISTEN`s on all three channels and prints or
forwards the payloads, routing on `tool` and `event`. It proves the shared format works and is the
thing a rota copies. It stays an example, not a component: paging is still the deployment's job.

### 7. Release the overview

Update this page and the PDF once 1 to 3 are decided: correct the version line, add the
`make install` caveat, and link each tool's INSTALL.md as they appear.

## Open questions

- One repository or three? Today each tool is its own directory. A monorepo makes the shared matrix
  and contract easy; three repos keep "install only what you need" literal. Recommendation: three
  repos plus this directory as the umbrella, since pg_lock_tree is already standalone.
- Should there be a meta-extension (`CREATE EXTENSION pg_incident_watch CASCADE`) that requires all
  three? Cheap to add, but it contradicts "install only what you need" as the headline. Recommend not
  until someone asks.
- Does the umbrella ever offer a single "what's wrong right now" view across installed tools? It
  would be the obvious first query in an incident, and it is also how this becomes a dashboard.
