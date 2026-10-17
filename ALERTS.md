# The pg_incident_watch alert contract

Every tool in this family announces itself on a PostgreSQL `NOTIFY` channel with a JSON payload. A
listener that wants to know about incidents from all of them should be able to write **one** parser
that routes on two fields and ignores everything it does not recognise.

This file is that agreement. It is small on purpose: a contract nobody can hold in their head is a
contract nobody will implement.

- `pg_lock_tree` implements it, since 1.1.11. See its `docs/alerting.md`, and the shipped payloads
  [below](#pg_lock_trees-payloads-as-shipped).
- `pg_bloat_cause` and `pg_limit_runway` now ship code, but neither sends on the channel yet. The
  contract was written before either had code, deliberately, so that neither had to invent a payload
  shape locally; neither has implemented the five required keys so far.

The payload contract itself does not depend on the PostgreSQL version. The family's version floor,
PostgreSQL 14 and later, is decided in the README, step 2.

## Required keys

Present in **every** payload from **every** tool.

| key | type | meaning |
|---|---|---|
| `tool` | string | Which extension sent this. One of `pg_lock_tree`, `pg_bloat_cause`, `pg_limit_runway`. |
| `channel` | string | The channel it was sent on. Defaults to the tool's name. |
| `event` | string | `alerting` or `cleared`. See below. `escalated` is reserved and sent by no tool. |
| `subject` | string | What the alert is about, and **stable across the samples of one incident**. This is the dedup key. |
| `sampled_at` | timestamptz | When the tool formed this payload: the `NOTIFY` time, `statement_timestamp()` in `pg_lock_tree`, not the time of a stored sample. An alert is about the live state, and there is no sampled instant behind it. The name promises more than that, but it has shipped, and rule 1 forbids renaming a key. |

### `subject` is the part that is easy to get wrong

An alert is one problem noticed many times. The payload is sent again on every escalation, and a
second incident may start before the first has cleared. `subject` is what lets a listener tell those
apart, so it must be **stable for the lifetime of one problem** and **different for two problems that
merely look similar**.

- **Session-rooted** (`pg_lock_tree`): the prepared transaction's `root_object` where there is one,
  otherwise the root pid. A prepared transaction has no session to name, so the lock name is the only
  identity available and pid alone would collide with any live session. Shipped as
  `coalesce(nullif(root_object, ''), 'pid ' || root_pid)`, so a session root reads `pid 179`. This is
  the pair that has keyed `pg_lock_tree`'s alert state since 0.8, when every prepared transaction was
  `root_pid` 0 and two of them collided into one alert. `application_name` is the weaker identity: it
  is nullable, it is not part of the alert table's primary key, and unrelated blockers routinely share
  one, so adopting it would merge their alerts the same way two prepared transactions once did. A
  prepared transaction has no `application_name` at all, so it would fall through to null rather than
  collide; the collision it introduces is a different one, not the same one.
- **Table-rooted** (`pg_bloat_cause`): the schema-qualified relation name. Not the OID, because a
  listener reading a log a week later cannot resolve an OID.
- **Limit-rooted** (`pg_limit_runway`): the limit's identity, such as `sequence public.orders_id_seq`
  or `xid wraparound`. Whatever makes it nameable in a message to a human.

A tool whose natural subject changes between samples has a modelling problem, not a formatting one,
and should say so rather than emit a subject that is subtly unstable.

### `event`

| value | meaning |
|---|---|
| `alerting` | A notification about a standing incident: the first for this subject, or a later one that is materially worse than at the last notification. |
| `cleared` | The condition is gone. Once. |

The family uses **two** event values, `alerting` and `cleared`. **Escalation is not a third event**: it
is carried by two payload fields that any escalating tool sends, `level` (the severity now) and
`previous_level` (the severity at the last notification). A consumer tells an onset from an escalation
on the same `alerting` event: `previous_level` is null at onset, and set and lower than `level` at an
escalation.

This was decided rather than assumed. A new event value would have meant every consumer writing a
branch for something the payload can already say, and the escalation rule is unchanged either way:
materially worse is measured against the **last notification**, not the last sample. `pg_lock_tree` is
the first tool to send `level` and `previous_level`, in 1.2.0.

`escalated` was in the vocabulary from the first draft. Rule 2 forbids removing a value, so it stays
defined, but **no tool sends it**, and nothing should treat its absence as a fault.

### Escalation, as `pg_lock_tree` decides it

What "materially worse" means is each tool's own definition. `pg_lock_tree`'s, as shipped, is any of
three, each compared against the high-water mark stored at the **last notification**, never against
the previous sample:

- **wider**: more sessions blocked than at the last notification;
- **deeper**: a longer chain than at the last notification;
- **longer**: the longest wait has at least **doubled** since the last notification (30s, 1m, 2m,
  4m, ...), and only when the operator set a wait threshold at all.

The previous-sample comparison is the one to avoid: a wait grows continuously, so "longer than last
time" is true on every sample and would notify every sample.

### `pg_lock_tree`'s payloads, as shipped

Onset, from `lock_tree_notify()`. Escalations currently send this same shape with the same `event`:

```json
{"tool":"pg_lock_tree","subject":"pid 179","sampled_at":"2026-10-09T09:12:04.118+01:00",
 "channel":"lock_tree","event":"alerting","root_pid":179,"root_object":null,
 "application_name":"nightly_batch","blocked_sessions":12,"max_depth":3,"longest_wait":"1m30s",
 "waiting_for":"relation public.ledger"}
```

Clearing, from `lock_tree_notify_resolved()`. The `subject` is built by the same expression, so a
listener can pair it with the onset:

```json
{"tool":"pg_lock_tree","subject":"pid 179","sampled_at":"2026-10-09T09:21:40.502+01:00",
 "event":"cleared","channel":"lock_tree","root_pid":179,"root_object":null,
 "application_name":"nightly_batch","blocked_at_most":40,"notified_count":3}
```

The channel in both examples is `lock_tree`, which is rule 3's short name rather than an exception
to it.

`blocked_at_most` and `notified_count` are `pg_lock_tree`'s own keys: what the incident peaked at, and
how many notifications it took. Values above are illustrative; the key set and order are the shipped
ones.

## Optional keys

| key | meaning |
|---|---|
| `summary` | One human sentence. Deliberately optional: it is the only key that needs translation, and a tool with no sensible sentence should omit it rather than emit a placeholder. |

## Rules

1. **Keys are only ever added, never removed or renamed.** A consumer must ignore keys it does not
   recognise. This is `pg_lock_tree`'s existing rule and it is the whole reason adding `tool` is not
   a breaking change.
2. **Values are only ever added within a key.** `event` gains vocabulary; it does not lose any.
3. **One channel per tool**, named for the tool's short name, so a listener can `LISTEN` to exactly
   what it routes: `lock_tree`, `bloat_cause`, `limit_runway`. The short name rather than the full one
   because `pg_lock_tree` shipped as `lock_tree` and renaming a channel that listeners already use
   moves them off it silently, which is not a failure anyone would notice.
   A shared `incident_watch` channel was considered and rejected: it would mean every consumer parses
   every payload to route it, which is the problem `tool` exists to solve.
   A listener should route on `tool`, which is correct whichever channel a tool sends on.
4. **Payloads stay small.** PostgreSQL **refuses** an oversized `NOTIFY`; it never truncates. Measured
   on PostgreSQL 14, 18.6 and 19beta4: a 7999-byte payload is sent, and 8000 bytes or more is refused
   with `payload string too long`. The channel name's length makes no difference, because the limit
   applies to the payload alone. In a PL/pgSQL sender the error aborts the send, so the caller sees an
   error rather than a quiet omission. Treat 7999 bytes as a hard ceiling, not a target. No unbounded
   arrays: a count and one example, not the list.
5. **No query text and no credentials in a payload.** A channel is readable by any role that can
   `LISTEN`, and payloads end up in pagers and chat logs. Name the statement by its `query_id`, or by
   a lock or relation name, and let the reader look up the text with the privileges they have.
6. **Deduplication is the sender's job, not the listener's.** A listener that receives three
   `alerting` messages for one subject has received a bug, and the right response is to report it.

## Adding a tool

Copy the five required keys. Send `alerting` once and `cleared` once per subject. If the tool has a
materially-worse threshold, send `level` and `previous_level` on the `alerting` event and say what
"materially worse" is in its own documentation. Write its tests to assert the required keys are
present, which is the check that keeps the family a family.