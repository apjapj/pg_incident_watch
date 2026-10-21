-- scripts/first-five-minutes.sql: the three first queries, run without assuming which tools are
-- installed. Companion to docs/first-five-minutes.md.
--
-- Run as a role with the grants from the page:
--   psql -X -f scripts/first-five-minutes.sql
--
-- No \gexec. The action queries are not run by this script at all; it prints what is available and
-- leaves the choice to the reader.

\set ON_ERROR_STOP 1
\pset pager off

\echo ''
\echo '== pg_lock_tree: what is stuck now'
SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_lock_tree') AS has_lock_tree \gset
\if :has_lock_tree
SELECT * FROM lock_tree_text();
\else
\echo 'pg_lock_tree is not installed; skipping the live tree.'
\endif

\echo ''
\echo '== pg_bloat_cause: what is slowing down'
SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_bloat_cause') AS has_bloat_cause \gset
\if :has_bloat_cause
SELECT relname, dead_rows, dead_pct, cause, cause_detail
  FROM bloat_cause
 LIMIT 10;
\else
\echo 'pg_bloat_cause is not installed; skipping the dead-row findings.'
\endif

\echo ''
\echo '== pg_limit_runway: what will break next'
SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_limit_runway') AS has_limit_runway \gset
\if :has_limit_runway
SELECT kind, object, until_date, state, detail
  FROM limit_runway
 LIMIT 10;
\else
\echo 'pg_limit_runway is not installed; skipping the limit findings.'
\endif

\echo ''
\echo 'Done. Empty results are valid on a quiet database. Read one action row before running it.'
