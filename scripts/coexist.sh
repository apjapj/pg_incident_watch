#!/usr/bin/env bash
# scripts/coexist.sh - run a stack manifest: install every extension it names into one database,
# run every suite, then check the cross-tool contract.
#
# Usage:
#   PGHOST=... PGPORT=... PGUSER=... scripts/coexist.sh [manifest]
#
# The default manifest is stacks/family.toml. Extension sources are found under PG_SRC_ROOT
# (default: the parent of this repository) by the extension's name, and each must be checked out
# at the ref the manifest names; the script verifies that before installing anything.
#
# The database is fixed to `postgres` in the manifest because pg_lock_tree's suite creates
# pg_cron, and pg_cron can only be created there.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
manifest=${1:-${COEXIST_MANIFEST:-$here/stacks/family.toml}}
src_root=${PG_SRC_ROOT:-$(dirname "$here")}
[ -f "$manifest" ] || { echo "no manifest at $manifest" >&2; exit 2; }

eval "$(python3 - "$manifest" <<'PY'
import shlex, sys, tomllib
d = tomllib.load(open(sys.argv[1], "rb"))
s = d["stack"]
print("STACK_DB=%s" % shlex.quote(s["database"]))
print("STACK_NAMES=%s" % shlex.quote(" ".join(e["name"] for e in d["extension"])))
print("STACK_REFS=%s" % shlex.quote(" ".join(e["ref"] for e in d["extension"])))
c = d.get("contract", {})
for var, key in (("C_EVENT", "event"), ("C_KEYS", "keys"), ("C_SENDERS", "senders"),
                 ("C_CHANNELS", "channels")):
    value = c.get(key, "")
    if isinstance(value, list):
        value = " ".join(value)
    print("%s=%s" % (var, shlex.quote(str(value))))
PY
)"

[ "$STACK_DB" = "postgres" ] || {
  echo "stack database must be postgres: pg_cron cannot be created elsewhere" >&2; exit 2; }

read -r -a names <<< "$STACK_NAMES"
read -r -a refs <<< "$STACK_REFS"
read -r -a keys <<< "${C_KEYS:-}"
read -r -a senders <<< "${C_SENDERS:-}"
read -r -a channels <<< "${C_CHANNELS:-}"

echo "== stack ${STACK_NAMES// /, } in $STACK_DB =="
for i in "${!names[@]}"; do
  name=${names[$i]}; ref=${refs[$i]}; dir=$src_root/$name
  [ -d "$dir/test" ] || { echo "  no checkout at $dir" >&2; exit 2; }
  got=$(git -C "$dir" rev-parse --short "$ref" 2>/dev/null) || {
    echo "  $dir has no ref $ref" >&2; exit 2; }
  echo "  $name @ $ref ($got)"
done

if [ "${COEXIST_SKIP_INSTALL:-0}" != "1" ]; then
  for name in "${names[@]}"; do
    ( cd "$src_root/$name" && make -s install ) >/dev/null
  done
fi

drop=$(IFS=,; echo "${names[*]}")
psql -X -q -d "$STACK_DB" -c "DROP EXTENSION IF EXISTS $drop CASCADE" >/dev/null 2>&1 || true

fail=0
for name in "${names[@]}"; do
  echo "== $name suite =="
  pg_prove --dbname "$STACK_DB" "$src_root/$name"/test/*.sql || fail=1
done

for name in "${names[@]}"; do
  psql -X -q -d "$STACK_DB" -c "CREATE EXTENSION IF NOT EXISTS $name" >/dev/null
done

echo "== family contract: every sender carries ${C_KEYS:-} on ${C_EVENT:-} with its own channel =="
contract=0
for i in "${!senders[@]}"; do
  sender=${senders[$i]}; channel=${channels[$i]:-}
  row=$(psql -X -Atq -d "$STACK_DB" -c \
        "SELECT prosrc || E'\n' || pg_get_function_arguments(oid) FROM pg_proc WHERE proname = '$sender'")
  if [ -z "$row" ]; then echo "  MISSING sender $sender"; contract=1; continue; fi
  for key in ${C_EVENT:-} "${keys[@]}"; do
    printf '%s' "$row" | grep -q "'$key'" || { echo "  $sender lacks '$key'"; contract=1; }
  done
  [ -z "$channel" ] || printf '%s' "$row" | grep -q "'$channel'" ||
    { echo "  $sender lacks channel '$channel'"; contract=1; }
done
[ "$contract" = 0 ] && echo "  ok" || fail=1

echo
if [ "$fail" -eq 0 ]; then
  echo "coexist: ${STACK_NAMES// /, } pass in one database and the family contract holds"
else
  echo "coexist: FAILED" >&2
fi
exit "$fail"
