# Clean drop: what each extension must show

**Status: specification, no code.** Written 2026-10-21 for the internal lifecycle capture and the
REMOVE band. It is the answer to "what does a clean `DROP EXTENSION` look like?" before a shared
snapshot tool exists. The method is a catalogue snapshot diff around the drop; this note fixes the
expected result, not the implementation.

Until the shared snapshot tool is pinned, no extension gets a one-off uninstall test. The CI check
adopts the shared helper once it exists.

## The method this is written for

1. Install the extension at the version under test.
2. Exercise it enough that its tables have rows: sample or alert at least once where the extension
   has writers, and call one read entry point.
3. Take snapshot A: extension membership, objects by class, relation row counts and sizes,
   `pg_extension_config_dump` rows, extension-owned schemas, ACLs and comments.
4. `DROP EXTENSION <name>` with **no CASCADE**.
5. Take snapshot B, and diff A to B.
6. Reinstall the extension and check it still installs cleanly. A drop that leaves the name
   unusable is not clean.

The drop itself must succeed. If a user object depends on the extension, the correct result is a
refusal that names the dependent, not a cascade. The test records the refusal and removes the
dependent, then retries.

## The common pass criteria

After `DROP EXTENSION`, for every extension:

- `pg_extension` has no row for the name.
- `pg_depend` has no members pointing at the old extension OID, and no extension-owned objects
  remain by OID.
- Every function, view, table, index, sequence, type, cast, operator, operator class, event trigger
  and comment the extension created is gone. No object in the extension's schema survives unless
  the schema existed before the install.
- No `pg_extension_config_dump` entry survives for a table of that extension.
- No extension table survives with its data. **The history tables are removed by the plain
  `DROP EXTENSION`; no `DROP TABLE` step is needed or wanted.** Losing sampled history, alerts,
  deadlock records and archive rows is the expected result, and the removal page says so.
- No extension-owned role survives. The extensions create none today; a future one would fail this
  check.
- The extension's GUCs are gone from `pg_settings` in a fresh session. Custom placeholders left in
  an already-running session are session state, not a catalogue leftover.
- `pg_available_extensions` still lists the package. The package is installed on the host even when
  the extension is not created in this database; that is not a leftover.
- Extensions the tool optionally uses are untouched. `pgstattuple` is a separate extension and must
  survive a `pg_bloat_cause` drop.

## `pg_lock_tree`

Required objects include the `lock_tree` view, its read and rendering functions (`lock_tree_roots`,
`lock_tree_root_holds`, `lock_tree_deadlock_cycle`, `lock_tree_text`, `lock_tree_summary`,
`lock_tree_statements`, `lock_tree_actions`, `lock_tree_command`, `lock_tree_deadlocks`,
`lock_tree_deadlock_participants`, `lock_tree_duration*`, `lock_tree_history_size`,
`lock_tree_archive_find`, and the rest of the older read functions), the sampler and pruner, and
the writer-side alert functions.

Tables that must be gone with their rows:

| Table | What is lost |
| :-- | :-- |
| `lock_tree_history` | sampled lock trees and the first query text kept under `lock_tree.history_query` |
| `lock_tree_history_archive` | the cold archive, including its indexes |
| `lock_tree_deadlock` | deadlock-counter samples and deltas |
| `lock_tree_alert` | notification state, so the next install starts with no memory |

Settings: `lock_tree.history_query` and `lock_tree.actions` must no longer appear as extension
settings in a fresh session. `lock_tree_sample()` and the archive functions are extension members
and are removed with the drop.

A dependent user view on `lock_tree` must block the drop by name. That is a clean refusal, not a
failure of the drop test.

## `pg_bloat_cause`

Required objects include the `bloat_cause` view; `bloat_cause_findings`, `bloat_cause_text`,
`bloat_cause_holder`, `bloat_cause_command`, `bloat_cause_measure`, `bloat_cause_context`,
`bloat_cause_age`, `bloat_cause_sample`, `bloat_cause_prune`, `bloat_cause_notify` and
`bloat_cause_notify_resolved`.

Tables that must be gone with their rows:

| Table | What is lost |
| :-- | :-- |
| `bloat_cause_history` | sampled dead-row series, holder context and any opt-in `holder_query` text |
| `bloat_cause_alert` | notification state and escalation level |

Settings: `bloat_cause.holder_query` must no longer appear as an extension setting in a fresh
session. `pgstattuple` must still be installed if it was installed before: it is not a dependency and
the drop must not touch it.

## `pg_limit_runway`

Required objects include the `limit_runway` view; `limit_runway_sequences`,
`limit_runway_projection`, `limit_runway_findings`, `limit_runway_unwatched`, `limit_runway_text`,
`limit_runway_urgency`, `limit_runway_command_row`/`limit_runway_command`,
`limit_runway_sample`, `limit_runway_prune`, `limit_runway_notify` and
`limit_runway_notify_resolved`.

Tables that must be gone with their rows:

| Table | What is lost |
| :-- | :-- |
| `limit_runway_history` | sampled positions, limits and epochs used for rate projection |
| `limit_runway_alert` | notification state, urgency high-water mark and escalation level |

Settings: `limit_runway.sample_min_used` must no longer appear as an extension setting in a fresh
session.

## The fourth repository

The family is three SQL extensions plus the `pg_incident_watch` umbrella. The umbrella has no
`.control` and no SQL objects, so there is nothing to drop. Its contract is checked by installing
the three extensions, running the listener, and then dropping them in any order. The listener is a
host-side script and is not an extension member; it must still work after the three drops, with no
extension-specific residue in the database.

## What is not a leftover

These are expected and must not be reported as drop residue:

- `pg_available_extensions` / `pg_available_extension_versions` rows. The package remains installed
  on the host.
- `pg_stat_statements` rows for calls made while the extension existed. They belong to that
  extension, not to this one.
- Rows in a shared table the extension was pointed at by configuration. None of the three creates
  or owns one.
- Custom GUC placeholders in a session that ran the extension before the drop. A fresh session is
  the check.
- `LISTEN` registrations. They are session state, not catalogue objects.

## Checks to build in the shared tool

These are requirements for the shared snapshot tool, not code in this repository:

1. Clean drop, no dependents: empty diff for every object class, every history and alert table
   gone with its data, no config-dump rows, no extension GUCs in a fresh session.
2. Dependent object: `DROP EXTENSION` refuses and names the dependent; the test records the refusal
   without cascade, removes the dependent and retries.
3. Reinstall after drop: the same version installs and its view or primary entry point answers.
4. Optional extension untouched: `pg_bloat_cause` drop leaves `pgstattuple` installed.
5. Reversed family order: dropping the three in each order leaves no residue and the listener still
   starts.
6. A drop with sampled data: specifically assert that `lock_tree_history`,
   `bloat_cause_history` and `limit_runway_history` are gone without a separate `DROP TABLE`.
