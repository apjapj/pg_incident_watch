# Scope decisions, 2026-10-19

Eleven questions that had been carried as "open" across the three tools and the umbrella. Each is
answered here so the next person can tell a decision from an omission. None of these changes code;
where a decision describes current behaviour, this says where that behaviour is documented.

**Revised 2026-10-21:** item 2 now defers to the newer `pg_bloat_cause` decision. The earlier wording
here said TOAST tables get their own rows over threshold; that is no longer the decision.

## pg_bloat_cause

**1. Index bloat is out of scope.**
B-tree bloat has different causes (deletion patterns, no deduplication on older indexes) and a
different fix (`REINDEX CONCURRENTLY`). Keeping it out keeps the tool's answer to "what is slowing
down" about table dead rows and their cause. A separate tool or a separate feature can own it.

**2. TOAST is folded into the parent, never its own row.**
The operational decision lives in
[`pg_bloat_cause/docs/index-and-toast.md`](https://github.com/apjapj/pg_bloat_cause/blob/main/docs/index-and-toast.md):
once implemented, TOAST is a secondary line on the parent when it is material, never a row for
`pg_toast.pg_toast_<oid>` and never the primary cause. This replaces the 2026-10-19 wording that gave
TOAST its own row over threshold. `pg_bloat_cause` does not implement the line yet.

**3. The estimate stays visible per row: `dead_rows_source` is kept.**
No extra prose marker is needed. Every row and payload already says `estimated` or `measured`, which
is the distinction that matters when someone is about to act on a number.

**4. The error in `n_dead_tup` is documented, not coded around.**
It is an estimate that resets on a statistics reset and after crash recovery on every version. The
docs say so, and `dead_rows_source` stays `estimated`; the tool does not pretend it can detect a
reset it cannot see.

## pg_limit_runway

**5. The database horizon is already cluster-wide; the relation checks are not.**
`limit_runway_findings()` and the sampler read `pg_database` (`datfrozenxid`, `datminmxid`,
`datconnlimit`), which is cluster-wide from any database, as are replication slots and roles. The
relation-level work (tables, sequences, partitions) reads the current database's catalogs. The
`pg_limit_runway` README's open question already states this split; this decision keeps it and
documents it plainly rather than adding a fan-out, because there is no per-database horizon to fan
out.

**6. Disk space is out of scope.**
The tool is about limits visible inside PostgreSQL. Free space on the filesystem, WAL volume and
tablespace capacity are the operating system's and the monitoring stack's job.

**7. Password expiry stays separate from `pg_pwreset`.**
`VALID UNTIL` is one of the limits this tool reports. Managing passwords is `pg_pwreset`'s job; the
two do not cross-reference or depend on each other.

**8. No configurable limits in v1.**
Wait for users to ask. Thresholds and ignore lists are the first thing to add if a real deployment
needs them, and adding them now guesses at the shape.

## The umbrella

**9. No monorepo.**
Three repositories plus this umbrella. Each tool stays installable on its own, and the shared
contract and stack are tested from here. A monorepo would make the shared matrix marginally easier
and make "install only what you need" less literal.

**10. No meta-extension.**
No `CREATE EXTENSION pg_incident_watch CASCADE` until someone asks. It contradicts the headline
promise and adds an install step that hides which tools are present.

**11. No cross-tool dashboard.**
No single "what is wrong right now" view spanning installed tools. It is the obvious first query in
an incident and it is also how this becomes a dashboard; that is already what the tools' views and
the listener are for. Wiring them to a dashboard is the deployment's decision.
