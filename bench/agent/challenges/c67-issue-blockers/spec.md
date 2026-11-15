# issue-tracker: blocking relations

The program in this directory is a working in-memory issue tracker driven by a command script on stdin (workflow, issues, queries, views, bulk operations, an audit log and reports). Add blocking relations between issues. Everything it does today must stay exactly as it is, including every message, error order and output format.

## New commands

Both take two issue ids (words, same id syntax and errors as every other command: `7` or `#7`, `bad issue id 'X'`, `no such issue #N`; the first id is checked before the second).

- `block ID BLOCKER`: record that `ID` is blocked by `BLOCKER`. Usage error: `usage: block ID BLOCKER` (not exactly two words). Then, in this order, the errors:
  1. id errors (the id of `ID`, then of `BLOCKER`);
  2. `#ID cannot be blocked by itself`;
  3. `#ID is in final state 'S'` (the blocked issue must not be in a final state; `BLOCKER` may be in any state);
  4. `#ID is already blocked by #K`;
  5. `blocking #ID by #K would create a cycle` when `BLOCKER` is, directly or through other issues, blocked by `ID`.

  On success: clock +1, `updated = t` on `ID`, the log gets `blocked by #K` for `ID`, and `#ID is now blocked by #K` is printed.
- `unblock ID BLOCKER`: usage `usage: unblock ID BLOCKER`; id errors as above; `#ID is not blocked by #K` when there is no such relation (final states are not checked here). On success: clock +1, `updated = t` on `ID`, log `unblocked from #K`, prints `#ID is no longer blocked by #K`.

## Effects elsewhere

- `move` (and so `bulk move`) to a **final** state fails when the issue still has an open blocker (a blocker that still exists and is not in a final state). The error is `cannot move #ID to S: blocked by #A, #B` listing the open blockers by ascending id. It is checked after the guard-field check (`missing ...`) and before anything changes. Moves to non-final states are never affected.
- `show` prints one extra line `  blocked by: #A, #B` (all blockers, ascending, including those already in a final state) between the `reporter:` and `created:` lines, only when the issue has at least one blocker. Issues without blockers print exactly as before.
- `delete` removes the deleted issue from every other issue's blockers (without changing the clock or the log of those issues beyond what `delete` already does).

Everything else (queries, views, reports, other commands) is unchanged.
