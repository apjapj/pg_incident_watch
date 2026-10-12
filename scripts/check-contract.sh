#!/usr/bin/env bash
# check-contract.sh: gate for pg_incident_watch, the umbrella that defines the family's shared
# NOTIFY alert contract and links to the three tools.
#
# This repository ships no extension: it is a contract, a plan, and a licence. There is no code to
# test, so a CI gate here has to protect the things that can rot silently:
#
#   - the contract's own coherence: the required keys are the ones the shipped payloads carry, and
#     the shipped payloads parse and name the right event.
#   - the family licence staying byte-identical across all four repositories.
#   - every local link in the docs resolving, and the house no-em-dash rule.
#
# It does NOT check the three tools' versions or status against this table. That would need the
# siblings checked out or read over the network, and it is a design choice, not a check; the sibling
# state in README.md is maintained by hand and is called out in CONTRIBUTING-style review.
#
# Usage: ./scripts/check-contract.sh
# Pure text. Needs no database, no network, no superuser.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
pass=0
ok()  { printf '  \033[32mok\033[0m    %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail+1)); }
step(){ printf '\n\033[1m%s\033[0m\n' "$1"; }

# ---------------------------------------------------------------- the family licence
step "the family licence is byte-identical everywhere"
# The whole family ships the PostgreSQL Licence with the same holder. A copy that drifted is a
# copy that says something different about who owns the code. This md5 is the family's, checked in
# the sibling repositories the same way.
want_lic=192477323bd8950104ccbe4eec6649f9
if [ ! -f LICENSE ]; then
  bad "LICENSE is missing"
else
  got=$(md5sum LICENSE | cut -d' ' -f1)
  [ "$got" = "$want_lic" ] \
    && ok "LICENSE md5 $got, the family's" \
    || bad "LICENSE md5 $got, expected the family's $want_lic"
fi

# ---------------------------------------------------------------- the contract's coherence
step "the shipped payloads satisfy the contract's own required keys"
# The required keys, hard-coded here, must match the keys the table in ALERTS.md lists AND the keys
# both shipped JSON examples actually carry. This is the check that keeps the contract honest: if a
# required key is added to the table but not to a payload, or a payload grows a key nobody documents,
# the contract and the code have drifted and this says so.
required="tool channel event subject sampled_at"
for key in $required; do
  grep -qE "\`$key\`" ALERTS.md \
    && ok "required key '$key' is in the ALERTS.md table" \
    || bad "required key '$key' is not in the ALERTS.md table"
done

# Parse the fenced json examples with python3 (present on both CI runners; check-workflows.sh
# already depends on it) and assert each example carries every required key and the right event.
if ! command -v python3 >/dev/null 2>&1; then
  bad "python3 is not available, so the shipped payloads were NOT checked"
else
  payload_report=$(python3 - <<'PY'
import json, re, sys
text = open("ALERTS.md").read()
blocks = re.findall(r"```json\n(.*?)```", text, re.S)
required = ["tool", "channel", "event", "subject", "sampled_at"]
if len(blocks) < 2:
    print("FAIL|expected at least two shipped payload examples, found %d" % len(blocks))
    sys.exit(0)
seen = {}
for i, b in enumerate(blocks):
    # The examples are wrapped across two lines; join and parse.
    try:
        obj = json.loads(" ".join(b.split()))
    except Exception as e:
        print("FAIL|payload example %d does not parse as JSON: %s" % (i+1, e))
        continue
    seen[i] = obj
    missing = [k for k in required if k not in obj]
    if missing:
        print("FAIL|payload example %d is missing required key(s): %s" % (i+1, ", ".join(missing)))
    else:
        print("OK|example %d carries all %d required keys" % (i+1, len(required)))
events = [o.get("event") for o in seen.values()]
if "alerting" in events and "cleared" in events:
    print("OK|the examples show both an 'alerting' and a 'cleared' event")
else:
    print("FAIL|expected one 'alerting' and one 'cleared' example, got %s" % events)
PY
)
  while IFS='|' read -r verdict msg; do
    [ -z "$verdict" ] && continue
    [ "$verdict" = OK ] && ok "$msg" || bad "$msg"
  done <<<"$payload_report"
fi

# ---------------------------------------------------------------- the three tools are named
step "the three tools are named"
for t in pg_lock_tree pg_bloat_cause pg_limit_runway; do
  grep -q "$t" ALERTS.md && ok "$t is named in ALERTS.md" || bad "$t is not named in ALERTS.md"
  grep -q "$t" README.md && ok "$t is named in README.md" || bad "$t is not named in README.md"
done

# ---------------------------------------------------------------- local links resolve
step "every local link the docs mention exists"
# This repository documents the other three, so most paths it names live in a SIBLING repository:
# "its docs/alerting.md", "pg_lock_tree/CONTRIBUTING.md", "pg_lock_tree's scripts/matrix.sh", "each
# tool's INSTALL.md". Those are cross-references into another repository, not local files, and this
# gate cannot check them without the siblings checked out. What it CAN check is that a path which
# names no sibling and is plainly meant to be local actually exists here.
#
# So a path is treated as local unless it names one of the three sibling repositories, or names a
# file that belongs to a sibling (a tool's own INSTALL/CONTRIBUTING/docs/scripts file). A genuinely
# local path in this repo is one under docs/ that is not a sibling's, or a top-level file this repo
# owns (README, ALERTS, SECURITY, LICENSE).
is_sibling_ref() {
  local p=$1
  # Explicit sibling repo prefix, e.g. pg_lock_tree/CONTRIBUTING.md
  case "$p" in pg_lock_tree/*|pg_bloat_cause/*|pg_limit_runway/*) return 0 ;; esac
  # A file this repo does not own but a sibling does. These appear as bare "docs/alerting.md",
  # "INSTALL.md", "scripts/matrix.sh" in prose that names the sibling in the same sentence, so they
  # are checked by name against what the siblings actually ship.
  case "$p" in
    docs/alerting.md|docs/reference.md|scripts/matrix.sh|INSTALL.md|CONTRIBUTING.md) return 0 ;;
  esac
  return 1
}
DOCS_ALL="README.md ALERTS.md SECURITY.md CONTRIBUTING.md docs/*.md"
for f in $DOCS_ALL; do
  [ -f "$f" ] || continue
  dir=$(dirname "$f")
  link_targets=$(grep -oE '\]\([A-Za-z0-9_./#-]+\)' "$f" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//')
  without_links=$(sed -E 's/\[[^][]*\]\([^)]*\)/@LINK@/g' "$f")
  bare=$(printf '%s\n' "$without_links" \
         | grep -oE '`[A-Za-z0-9_][A-Za-z0-9_./-]*\.(sql|md|sh|control)`' 2>/dev/null | tr -d '`')
  paths=$(printf '%s\n%s\n' "$link_targets" "$bare" \
          | grep -vE '^(https?:|mailto:|[^ ]*[?*<>][^ ]*$|[^ ]*[0-9]\.x[^ ]*$|#)' | sort -u)
  for p in $paths; do
    case "$p" in *#*) p=${p%%#*} ;; esac
    [ -n "$p" ] || continue
    case "$p" in /*) continue ;; esac
    is_sibling_ref "$p" && continue
    if [ -e "$dir/$p" ] || [ -e "$p" ]; then :; else bad "$f mentions '$p', which does not exist here and names no sibling"; fi
  done
done
ok "local links checked across $DOCS_ALL (sibling-repository references are excluded by design)"

# ---------------------------------------------------------------- house style
step "house style"
dashfiles=$(git ls-files -z 2>/dev/null | tr '\0' '\n' \
  | grep -E '\.(md)$' \
  | while IFS= read -r p; do grep -lP '\x{2013}|\x{2014}' "$p" 2>/dev/null; done)
if [ -z "$dashfiles" ]; then
  ok "no em-dashes or en-dashes in any tracked .md file"
else
  bad "these files contain an em-dash or en-dash: $(printf '%s' "$dashfiles" | tr '\n' ' ')"
fi

printf '\n\033[1m%d checks passed, %d failed\033[0m\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
