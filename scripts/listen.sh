#!/usr/bin/env bash
# scripts/listen.sh: the reference listener for pg_incident_watch, step 6 of the plan.
#
# One session, three LISTENs, every payload printed as it arrives, routed on `tool`.
#
# It proves the shared format works end to end, and it is the thing a rota copies. It stays an
# example rather than a component: paging is the deployment's job, and this deliberately does not
# do it. What it adds over bare psql is the contract check, so a payload that has lost a
# required key is visible at the moment it arrives rather than at 3am when someone asks why the
# page was empty.
#
# Usage:
#   scripts/listen.sh                          # all three channels, until interrupted
#   scripts/listen.sh --for 60                 # stop after 60 seconds
#   scripts/listen.sh --interval 2             # two seconds between polls
#   scripts/listen.sh lock_tree                # one channel only
#
# Connection comes from the standard libpq environment variables: PGHOST, PGPORT, PGDATABASE,
# PGUSER, PGPASSFILE and friends. There is no connection argument and no password on the command
# line, for the reason every credential script in this estate has the same reason.
#
# Requires: psql. `jq` is used to pretty-print when present, and without it the payload is
# printed as it arrived.
#
# Why this reads psql's own message rather than the NOTIFY_PAYLOAD variable. NOTIFY_PAYLOAD is
# the obvious way to do this and it does not work: psql only populates it when it is reading
# commands from a terminal, never from a script, verified on 18.6 with a file argument and with
# the file on stdin. In a script psql instead prints a client-side message of its own:
#
#   Asynchronous notification "lock_tree" with payload "{...}" received from server process with PID N.
#
# The payload inside that is the real payload, and the prefix and the terminator are fixed
# literals, so slicing between them is exact even when the payload itself contains double
# quotes, braces or commas. A payload is NOT valid JSON escaped here, so this is a slice and
# not a parse, which is the right trade: a payload that is not JSON still gets printed rather
# than dropped.
#
# Why polling at all: psql cannot block on a notification arriving. The sleep is what gives the
# session a moment in which to receive one. A psycopg2 listener blocks on the socket instead and
# has no interval at all; the README gives that variant for anyone who wants it. This one is
# here because psql ships with every PostgreSQL installation and this one runs anywhere.

set -uo pipefail
cd "$(dirname "$0")/.."

CHANNELS=(lock_tree bloat_cause limit_runway)
INTERVAL=0.5
DURATION=0

while [ $# -gt 0 ]; do
    case $1 in
        --for)      DURATION=${2:?--for needs seconds}; shift 2 ;;
        --interval) INTERVAL=${2:?--interval needs seconds}; shift 2 ;;
        -h|--help)  sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)         printf 'error: unknown option %s\n' "$1" >&2; exit 2 ;;
        *)          CHANNELS=("$@"); shift $# ;;
    esac
done

command -v psql >/dev/null 2>&1 || { printf 'error: psql is not on PATH\n' >&2; exit 2; }
HAVE_JQ=no
command -v jq >/dev/null 2>&1 && HAVE_JQ=yes

# Ticks. Zero seconds means run until interrupted, which is a long afternoon.
if [ "$DURATION" -gt 0 ]; then
    TICKS=$(awk -v d="$DURATION" -v i="$INTERVAL" 'BEGIN{printf "%d", (d / i) + 0.5}')
else
    TICKS=100000
fi

sql=$(mktemp); chmod 600 "$sql"
trap 'rm -f "$sql"' EXIT INT TERM

{
    printf '\\set ON_ERROR_STOP on\n'
    printf '\\pset pager off\n'
    printf '\\pset format unaligned\n'
    printf '\\pset tuples_only on\n'
    for c in "${CHANNELS[@]}"; do
        printf 'LISTEN %s;\n' "$c"
    done
    i=0
    while [ "$i" -lt "$TICKS" ]; do
        printf 'SELECT pg_sleep(%s);\n' "$INTERVAL"
        i=$((i+1))
    done
} > "$sql"

printf 'listening on : %s\n' "${CHANNELS[*]}" >&2
printf 'contract    : ALERTS.md, required keys are tool, channel, event, subject, sampled_at\n' >&2
printf 'printer     : %s\n' "$([ "$HAVE_JQ" = yes ] && echo 'jq, pretty-printed' || echo 'raw, jq not found')" >&2
printf 'ctrl-c to stop\n\n' >&2

# Contract rule 1: keys are only ever added, so a payload may legally carry keys this has never
# heard of, and that is not an error. Only a MISSING required key is, because a consumer cannot
# route without `tool` and cannot deduplicate without `subject`.
REQUIRED_JSON='["tool","channel","event","subject","sampled_at"]'

render() {
    local channel=$1 payload=$2
    local tool='-' event='-' subject='-' pretty=$payload

    if [ "$HAVE_JQ" = yes ] && printf '%s' "$payload" | jq -e . >/dev/null 2>&1; then
        tool=$(printf '%s' "$payload" | jq -r '.tool // "-"')
        event=$(printf '%s' "$payload" | jq -r '.event // "-"')
        subject=$(printf '%s' "$payload" | jq -r '.subject // "-"')
        pretty=$(printf '%s' "$payload" | jq -S . 2>/dev/null || printf '%s' "$payload")
        local missing
        # `[ $req[] as $k | select(has($k) | not) ]` collects the payload object once per key, and
        # join then tries to add an object to a string, so this needs `| $k` at the end of the
        # pipeline to yield the missing keys themselves. Without it jq errors, and with stderr
        # discarded the check silently never fired on any payload at all.
        missing=$(printf '%s' "$payload" | jq -r --argjson req "$REQUIRED_JSON" \
            '[ $req[] as $k | select(has($k) | not) | $k ] | join(", ")' 2>/dev/null)
        [ -n "$missing" ] && printf '  WARN  missing required key(s): %s\n' "$missing" >&2
    else
        printf '  WARN  payload is not valid JSON, printing it as it arrived\n' >&2
    fi

    printf '%s  %-12s %-9s %-14s %s\n' "$(date +%H:%M:%S)" "$event" "$tool" "$channel" "$subject"
    printf '%s\n' "$pretty" | sed 's/^/    /'
    printf '\n'
}

# Parse with bash parameter expansion rather than sed. The sed form needs a backreference inside
# a double-quoted string inside a sed script, which is three quoting layers for one field, and on
# the first run it produced an empty payload and an empty channel with no error in the summary.
# Slicing between fixed literals is exact and has no quoting hazards: the payload may contain
# quotes, braces and commas and it still comes out whole, because the terminator is a fixed
# string rather than a delimiter that could also appear inside the data.
split_line() {
    LINE_CHANNEL=''
    LINE_PAYLOAD=''
    case $1 in
        'Asynchronous notification "'*) ;;
        *) return 1 ;;
    esac
    local after_channel=${1#*notification \"}
    LINE_CHANNEL=${after_channel%%\"*}
    local after_payload=${1#*with payload \"}
    LINE_PAYLOAD=${after_payload%\" received from server process*}
    [ -n "$LINE_PAYLOAD" ]
}

psql -X -q -A -t -f "$sql" 2>/dev/null | while IFS= read -r line; do
    [ -n "$line" ] || continue
    if split_line "$line"; then
        render "$LINE_CHANNEL" "$LINE_PAYLOAD"
    else
        printf '  psql said: %s\n' "$line" >&2
    fi
done