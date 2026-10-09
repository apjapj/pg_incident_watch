# The pg_incident_watch alert contract

Every tool in this family announces itself on a PostgreSQL `NOTIFY` channel with a JSON payload. A
listener that wants to know about incidents from all of them should be able to write **one** parser
that routes on two fields and ignores everything it does not recognise.

This file is that agreement. It is small on purpose: a contract nobody can hold in their head is a
contract nobody will implement.

- `pg_lock_tree` implements it. See its `docs/alerting.md`.
- `pg_bloat_cause` and `pg_limit_runway` are design only. This contract was written before either
  has code, deliberately, so that neither has to invent a payload shape locally.

## Required keys

Present in **every** payload from **every** tool.

| key | type | meaning |
|---|---|---|
| `tool` | string | Which extension sent this. One of `pg_lock_tree`, `pg_bloat_cause`, `pg_limit_runway`. |
| `channel` | string | The channel it was sent on. Defaults to the tool's name. |
| `event` | string | One of `alerting`, `escalated`, `cleared`. See below. |
| `subject` | string | What the alert is about, and **stable across the samples of one incident**. This is the dedup key. |
| `sampled_at` | timestamptz | When the tool formed this payload. |

### `subject` is the part that is easy to get wrong

An alert is one problem noticed many times. The payload is sent again on every escalation, and a
second incident may start before the first has cleared. `subject` is what lets a listener tell those
apart, so it must be **stable for the lifetime of one problem** and **different for two problems that
merely look similar**.

- **Session-rooted** (`pg_lock_tree`): the prepared transaction's `root_object` where there is one,
  otherwise the root pid. A prepared transaction has no session to name, so the lock name is the only
  identity available and pid alone would collide with any live session.
- **Table-rooted** (`pg_bloat_cause`): the schema-qualified relation name. Not the OID, because a
  listener reading a log a week later cannot resolve an OID.
- **Limit-rooted** (`pg_limit_runway`): the limit's identity, such as `sequence public.orders_id_seq`
  or `xid wraparound`. Whatever makes it nameable in a message to a human.

A tool whose natural subject changes between samples has a modelling problem, not a formatting one,
and should say so rather than emit a subject that is subtly unstable.

### `event`

| value | meaning |
|---|---|
| `alerting` | First notification for this subject. Once per incident, not once per sample. |
| `escalated` | Materially worse than at the **last notification**, not than at the last sample. |
| `cleared` | The condition is gone. Once. |

`escalated` is optional per tool and is **not yet implemented by `pg_lock_tree`**, which sends
`alerting` for both onset and escalation. It is in the vocabulary now so that a consumer can write
the branch before any tool uses it. Deciding whether `pg_lock_tree` starts sending it is a behaviour
change and belongs in its own release, not in the one that adds `tool`.

## Optional keys

| key | meaning |
|---|---|
| `summary` | One human sentence. Deliberately optional: it is the only key that needs translation, and a tool with no sensible sentence should omit it rather than emit a placeholder. |

## Rules

1. **Keys are only ever added, never removed or renamed.** A consumer must ignore keys it does not
   recognise. This is `pg_lock_tree`'s existing rule and it is the whole reason adding `tool` is not
   a breaking change.
2. **Values are only ever added within a key.** `event` gains vocabulary; it does not lose any.
3. **One channel per tool**, named the tool, so a listener can `LISTEN` to exactly what it routes.
   A shared `incident_watch` channel was considered and rejected: it would mean every consumer parses
   every payload to route it, which is the problem `tool` exists to solve.
4. **Payloads stay small.** PostgreSQL truncates `NOTIFY` at 8000 bytes. No unbounded arrays.
5. **Deduplication is the sender's job, not the listener's.** A listener that receives three
   `alerting` messages for one subject has received a bug, and the right response is to report it.

## Adding a tool

Copy the five required keys. Send `alerting` once and `cleared` once per subject. If the tool has a
materially-worse threshold, implement `escalated` and say what it is in its own documentation. Write
its tests to assert the required keys are present, which is the check that keeps the family a family.