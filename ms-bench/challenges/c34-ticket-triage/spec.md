# Ticket triage

A help desk exports support tickets and a small rule file. Route every ticket to a queue, set its priority,
merge repeat reports, and print the work list per queue. The input is messy; bad lines are reported, not
fatal. All text is ASCII.

## Input

Lines are numbered from 1 (physical lines). Trim spaces and tabs from both ends of each line, then:

- Empty lines and lines starting with `#` are ignored.
- A line that starts with `[` is a section header. Exactly `[rules]` or `[tickets]` switches to that section;
  any other header records the problem `line N: unknown section` and leaves no active section.
- Any other line belongs to the active section. Lines with no active section (before the first header, or
  after an unknown header) are ignored without a problem.

The sections may appear in any order and any number of times. Rules are always applied to all tickets,
whatever the order of the sections.

### Rules section

Tokens are separated by runs of spaces and tabs.

- `now N`: the current time in minutes; `N` is 1 to 9 digits. The last valid `now` wins; the default is 0.
- `vip NAME`: marks a reporter (compared case-insensitively) as a VIP. Exactly one token after `vip`.
- `route WORD QUEUE P`: `WORD` is lowercased and must be one or more of `a-z0-9`; `QUEUE` is any token;
  `P` is exactly one of the single characters `1` to `5` (1 is most urgent).

Any other line in this section records `line N: bad rule`, as does a malformed `now`, `vip` or `route`.
`route` rules keep their file order.

### Tickets section

A ticket line is `id|reporter|created|subject|body`: split at `|` into at most 5 parts, so the body may
contain further `|` characters. Trim each part. A line with fewer than 5 parts, an `id` that is empty or
contains a space or tab, an empty `reporter`, a `created` that is not 1 to 9 digits, or an empty `subject`
records `line N: bad ticket` (the body may be empty). A valid line whose `id` was already used by an earlier
valid ticket line (compare exactly, case-sensitive; a ticket that gets merged below still uses its id)
records `line N: duplicate id` and is ignored.

## Processing a ticket

1. **Duplicates.** Normalise the subject: lowercase it; then repeatedly trim leading spaces/tabs and remove one
   leading `re:` or `fwd:` if present, until neither is there; then collapse every run of spaces/tabs into a
   single space and trim. If an earlier ticket has the same lowercase reporter and the same normalised
   subject, this ticket is *merged* into the earliest such ticket (its merged counter goes up by one) and
   needs no further processing.
2. **Routing.** Lowercase `subject + " " + body` and split it into tokens: maximal runs of `a-z0-9`. The first
   `route` rule (in file order) whose word equals one of the tokens decides the queue and the base priority.
   With no match the queue is `general` and the base priority is 3.
3. **Adjustments**, in this order, each lowering the number by one but never below 1: the reporter is a VIP;
   the ticket is stale, meaning `now - created >= 1440` (a ticket created after `now` is not stale).

## Output

For each queue, in ascending byte order of its name:

    queue <name> (<number of tickets in the queue>)
      <id> P<priority> <subject>[ (+<k> merged)]

with its tickets ordered by priority, then `created`, then `id` (all ascending, `id` in byte order). `<subject>`
is the trimmed subject exactly as written; the ` (+k merged)` suffix appears only when `k > 0`. Merged
tickets are not counted in the queue sizes. Then always print

    summary: tickets=<tickets listed> merged=<merged tickets> problems=<number of problems>

and, if there are problems, `problems:` followed by each message indented by 2 spaces, in file order.

Example input:

    [rules]
    now 3000
    vip Dana
    route refund billing 2
    route crash eng 1
    [tickets]
    t1|alice|100|App crash on start|stack trace attached
    t2|Dana|2900|Re: refund please|where is my money
    t3|alice|150|RE: re: app crash on start|same here
    t4|bob|2990|hello
    t5|bob|2990|Question|just asking

Output:

    queue billing (1)
      t2 P1 Re: refund please
    queue eng (1)
      t1 P1 App crash on start (+1 merged)
    queue general (1)
      t5 P3 Question
    summary: tickets=3 merged=1 problems=1
    problems:
      line 10: bad ticket
