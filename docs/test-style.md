# Test style: make the failure explain itself

**Status: style guide, not a rewrite order.** Apply it to a test file when you touch that file. A
dedicated pass per extension can follow, but a test run must not change its assertions to fit the
prose.

## Why

The assertion description is what a person sees when a test fails. A label such as "the guard" or
"the marker" only helps someone who already knows the file. A full sentence says what was expected
and therefore what went wrong.

## The rules

1. **Open with a short paragraph.** Say what the file proves, in one or two sentences, and why it
   matters: the incident or defect it guards against. Keep it shorter than the file's comments are
   today.
2. **Every assertion description is a full short sentence** with a subject and an expected outcome.
   Write "a table that crossed the 10% rung raises exactly one alert", not "the rung fires once".
3. **One idea per sentence.** Define a term the first time it is used. If the file says "marker" or
   "clear", say what that means in this test before using it as shorthand.
4. **Given, when, then in comments** when a scenario has steps: what is set up, what is done, what
   must be true. Put the comment next to the step it explains.
5. **No internal shorthand** unless the file defines it. When a test pins a decision, name the
   decision and its date, for example "decided 2026-10-19: the cleared-alert function sends nothing
   when it cannot tell recovery from a statistics reset".

## Worked example

Instead of:

> the guard in `bloat_cause_notify_resolved()` must mean "unknown, so no clear" and never
> "suppress alerts" ...

write:

> After a statistics reset, the cleared-alert function cannot tell whether a table recovered or its
> numbers were wiped, so it sends no "cleared" alert. This must not suppress new alerts: the alert
> function works from the current findings and ignores the reset marker.

## Proving a text rewrite is safe

A rewrite is text-only when the suite produces the same pass and fail result for every numbered
assertion before and after. Record both runs, and run the defects suite to prove it still catches the
same defects. If an assertion changes, the rewrite changed behaviour and is not text-only.

## Scope

This applies to the three extensions and the umbrella's own tests. It does not apply to the books,
which have their own voice guide and style review.
