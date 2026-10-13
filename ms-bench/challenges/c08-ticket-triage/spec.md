# Ticket triage

A support desk tool reads a log of commands, one per line, and answers each with one line. Blank lines
(empty or only spaces) are ignored and produce no output. A command is split on single spaces; the first
token is the command name (case-sensitive).

## Tickets

A ticket has an `ID` (one or more uppercase ASCII letters, a `-`, one or more digits: `T-1`, `BUG-204`),
a priority (`low` < `normal` < `high` < `urgent`), a title, an optional agent (lowercase ASCII letters,
one or more) and a status. Statuses: `new`, `assigned`, `in_progress`, `resolved`, `closed`. Each ticket
also counts how many times it was reopened.

## Commands

For every command the checks are made in this order, and the first failure prints its error line and
changes nothing: (1) unknown command name: `error: unknown command`; (2) wrong number of tokens:
`error: usage`; (3) argument syntax; (4) the ticket must exist: `error: unknown ticket <ID>` (an ID that
is not well formed is simply unknown); (5) the rules of the command. Success prints `ok` unless stated.

- `open <ID> <priority> <title...>`: needs at least 4 tokens; the title is everything after the third
  space (kept exactly, and must be non-empty). Syntax checks in order: ID well formed (`error: bad id`),
  priority one of the four names (`error: bad priority`). Then, if the ID exists, `error: <ID> already
  exists`. The new ticket is `new`, with no agent.
- `assign <ID> <agent>` (3 tokens): agent must be lowercase letters (`error: bad agent`). The ticket must
  not be `resolved` or `closed` (`error: <ID> is resolved` / `error: <ID> is closed`). Sets the agent
  (replacing any previous one); a `new` ticket becomes `assigned`.
- `start <ID>` (2 tokens): `new` fails with `error: <ID> has no assignee`; `assigned` becomes
  `in_progress`; `in_progress` fails with `error: <ID> already in progress`; `resolved`/`closed` fail with
  `error: <ID> is resolved` / `error: <ID> is closed`.
- `resolve <ID>` (2 tokens): only `in_progress` becomes `resolved`; any other status fails with
  `error: <ID> cannot be resolved from <status>`.
- `close <ID>` (2 tokens): only `resolved` becomes `closed`; otherwise `error: <ID> cannot be closed from <status>`.
- `reopen <ID>` (2 tokens): `resolved` or `closed` becomes `in_progress` (the agent is kept) and the
  reopen count goes up by one; otherwise `error: <ID> cannot be reopened from <status>`.
- `escalate <ID>` (2 tokens): a `closed` ticket fails with `error: <ID> is closed`; an `urgent` ticket
  fails with `error: <ID> is already urgent`; otherwise the priority goes up one level.
- `show <ID>` (2 tokens): prints `<ID> [<priority>] <status> agent=<agent or -> reopened=<n>: <title>`.
- `report` (1 token): prints several lines (no `ok`):
  1. `new=<a> assigned=<b> in_progress=<c> resolved=<d> closed=<e>` (ticket counts per status);
  2. for every agent that has at least one `assigned` or `in_progress` ticket, in byte order of the agent
     name: `<agent>: <ID> <ID> ...` listing those tickets by priority (highest first), ties by ID in byte
     order;
  3. if there are `new` tickets: `unassigned: <ID> <ID> ...`, in the same ticket order.

Lines 2 and 3 are omitted when empty.

Example input:

    open T-1 high Login page broken
    open T-2 low Typo in footer
    assign T-1 ann
    start T-1
    resolve T-2
    show T-1
    escalate T-1
    escalate T-1
    report

Output:

    ok
    ok
    ok
    ok
    error: T-2 cannot be resolved from new
    T-1 [high] in_progress agent=ann reopened=0: Login page broken
    ok
    error: T-1 is already urgent
    new=1 assigned=0 in_progress=1 resolved=0 closed=0
    ann: T-1
    unassigned: T-2
