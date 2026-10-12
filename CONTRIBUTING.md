# contributing: changing this, and releasing it

This repository ships no extension. It holds the family's shared contract
([ALERTS.md](ALERTS.md)), the plan, and the licence. So there is no SQL to install, no
test suite to run against a database, and no version to increment. What there is, is a
gate, and this file is how to work with it.

## The gate

```
./scripts/check-contract.sh
```

Seventeen checks, all pure text: the family licence stays byte-identical to the other
three repositories, the shipped payloads in ALERTS.md carry all five required keys, both
`alerting` and `cleared` appear, the three tools are named in both documents, local links
resolve, and no document contains an em-dash or an en-dash. It needs no database, no
network and no superuser, so it runs the same on your machine and in CI, on both GitHub
Actions and Forgejo.

CI also runs `bash -n` over every script in `scripts/`, so a shell file that does not
parse fails even if nothing calls it.

Run the gate before you push. It is cheap enough to sit in a pre-commit hook.

## What this repository does not check, and you must

These are the ways a change here can be wrong without the gate noticing.

- **Version and status claims.** The sibling table in the README and the release state in
  the sibling repositories are the most likely thing to go stale, and nothing here reads
  a tag from another repository. When you cut or release a sibling, re-read the table
  against the tags and the releases, not from memory. It has already been wrong twice: a
  sibling tagged but described as "not yet tagged", and another whose table named one
  tag where two existed.
- **Whether the three tools still match the contract.** The gate checks ALERTS.md's
  examples against ALERTS.md. It cannot check a payload that ships in
  `pg_lock_tree/pg_lock_tree--*.sql`, because that is another repository. When you
  change what a tool sends, re-read its release SQL and its `docs/alerting.md`.
- **Whether a link resolves somewhere else.** The gate checks links that point inside
  this repository, and excludes sibling-repository references by design. The three
  extension links point at repositories that are separate and are not fetched by the gate.
- **Whether a claim is true.** A sentence in the plan can be wrong and pass every check.
  That is what review is for.

## Changing the contract

`ALERTS.md` is the one document the other three implementations are held to, so a change
to it is a change to three repositories, not one.

- **Required keys are additive only and are never renamed.** `subject` is the
  deduplication key and its name has shipped since 1.1.11; renaming it would break every
  listener. If a key genuinely cannot be used as named, add a new one and leave the old.
- **Payload size is bounded.** The measured limit is 7999 bytes of payload, and the
  channel name does not count toward it. No unbounded arrays.
- **New keys must be documented in the table** and added to both examples, or the gate
  will not see them as required and a reader cannot tell what is contractual.

## Workflow policy

Three rules every workflow in this repository follows, so a change to one file does not
quietly break the posture the others keep:

- **Actions are pinned to a commit SHA**, with the release in a trailing comment:
  `actions/checkout@<40-hex> # v4.4.0`. A tag such as `@v4` is a moving reference: whoever
  controls the upstream tag controls what runs in this repository, and the change lands
  without a review here. To move it, resolve the tag yourself
  (`git ls-remote https://github.com/actions/checkout refs/tags/v4`), replace the SHA, and
  put the new version in the comment in the same commit, so the diff shows both.
- **`permissions: contents: read` at the top of every workflow.** No job here writes to
  the repository, creates a release, or needs a wider token. Stating it means a later
  change cannot quietly widen it, and it stops a workflow inheriting whatever the
  repository default happens to be.
- **The Forgejo and GitHub copies are kept deliberately parallel.** They differ only in
  `runs-on`, the job image note and the log-retention sentence. They are not kept in step
  by a generator, because the point of the second copy is that the public repository
  proves what the private one proves, and a generator is one more thing that can be
  right while both copies are wrong. When you change one, change the other, and say in the
  commit that you did.

## House style

No em-dashes or en-dashes in any document, comment, script or workflow. The gate checks
it, and a reader's eye catches it before anything else.

## Licensing

`LICENSE` is the PostgreSQL Licence and is byte-identical across all four repositories of
the family. The gate checks the md5. Do not reformat it, do not add a copyright line to
another file, and do not make it "more standard": the text is GitHub's PostgreSQL
template precisely so GitHub detects it and shows `PostgreSQL` in the sidebar.