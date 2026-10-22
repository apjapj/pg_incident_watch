# Which tool first

A fixed order for the first question: what do I look at first? Ask the six questions in order; the
first yes names the tool.

1. **Are sessions waiting or stuck now?**  
   Yes: [`pg_lock_tree`](https://github.com/apjapj/pg_lock_tree). It shows who blocks whom, the root
   blocker and the command to run.

2. **Is a table bloated, or is the disk filling?**  
   Yes: [`pg_bloat_cause`](https://github.com/apjapj/pg_bloat_cause). It says why dead rows are not
   being cleaned up and what to do next.

3. **Did an error name a limit or an expiry?**  
   Yes: [`pg_limit_runway`](https://github.com/apjapj/pg_limit_runway). It gives the current value,
   the limit and the date each limit is reached.

If none of those fits, **more tools are planned**. They are not named here until they are released.

## This is not a health check

A "no" means the question did not find the problem, not that the database is healthy. The tools say
what they checked and what they could not check; a missing tool is a gap, not a pass.

## Alternative install route

`CREATE EXTENSION` is the default for each tool. Where the extension files cannot be installed, or
`CREATE EXTENSION` is unavailable, the generated script route is the alternative: install, uninstall
and cumulative migration scripts under `scripts/sql/` in each tool's repository. It is not the
default, and the two routes must not be mixed in one database. The route is documented in each
tool's script-install-route documentation; `pg_limit_runway` is the pilot.
