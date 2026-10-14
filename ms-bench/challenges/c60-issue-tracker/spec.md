# issue-tracker

Implement an in-memory issue tracker driven by a command script on stdin: a configurable workflow with guarded state transitions, issue editing, a boolean query language with sorting, saved views, bulk operations, an audit log and reports. The exit status is always 0; every error is reported on stdout.

## Input and output framing

Stdin is a sequence of lines. Line endings may be `\n` or `\r\n`. A line that is empty or whose first non-blank character is `#` is skipped silently. Every other line is a command: the program first prints `> ` followed by the line with trailing whitespace removed (leading whitespace is kept), then the command's output lines. The only exception is the body of a `workflow` command (see below), whose lines are consumed without echo. An error is a single output line `error: MESSAGE`; a failed command changes nothing (except where stated for `bulk`). A command word is the first whitespace-separated word of the line; an unknown one prints `error: unknown command 'NAME'`.

Two argument styles are used. Commands documented with *words* split the rest of the line on whitespace (spaces and tabs). Commands documented with *tokens* (`create`, `edit`, `label`, `assign`, and the action part of `bulk`) split into tokens on whitespace, where a double quote starts a quoted section inside a token: everything up to the closing quote (spaces included) belongs to the token, and the quotes are removed. Inside quotes `\"` and `\\` stand for `"` and `\`. A token may mix quoted and unquoted parts (`title="two words"`). An unterminated quote is `error: unterminated quote`.

## Model

- **Logical clock**: an integer `t`, initially 0. Each command that changes something increments it by exactly one, as specified per command (no clocks are read). Unsuccessful commands, and `edit`/`label`/`assign` that change nothing, do not advance it.
- **Actor**: a name, initially `system`, set by `actor`. It is recorded in the log and on comments. **Today**: a date `YYYY-MM-DD`, initially `1970-01-01`, set by `today`; it is only used by `is:overdue` and the reports.
- **Issue** fields: `id` (integers from 1, never reused, also after `delete`), `title` (non-blank text), `state`, `priority` (`low`, `medium`, `high`, `critical`; default `medium`), `assignee` (text or absent), `reporter` (text; default the current actor), `points` (integer 0..1000000 or absent), `due` (a valid date `YYYY-MM-DD` or absent), `labels` (a set of lowercase labels), `comments` (list), `created` and `updated` (clock values).
- Dates are valid when year >= 1, month 1..12 and the day exists (leap years follow the Gregorian rule). Dates compare as strings. Integers are written as decimal digits without sign, without leading zeros (except `0` itself), at most 1000000. Labels match `[a-z0-9_-]+`; input labels are lowercased first, duplicates are merged, and labels are kept sorted bytewise.
- **Final states** are those declared `final:` in the workflow. An issue is *open* when its state is not final. An issue id argument is written `7` or `#7` (digits only, leading zeros allowed, at least 1), else `error: bad issue id 'ARG'`; if no such live issue exists, `error: no such issue #7`.

## workflow

`workflow` is followed by a block of lines up to a line that is exactly `end` after trimming (or the end of input). Blank lines and `#` comment lines inside the block are ignored. Other lines:

- `initial: NAME`, exactly one of them is required;
- `final: NAME, NAME, ...`, may repeat;
- `SRC -> DST, DST requires FIELD+FIELD, ...`: allowed transitions from `SRC`. Each comma separated entry is a target state, optionally followed by `requires` and one or more guard fields joined with `+`. Guard fields are `assignee`, `points`, `due`, `labels`, `reporter`. The same source may appear on several lines; the entries accumulate in order.

State names match `[a-z][a-z0-9_]*`. States are numbered in order of first appearance anywhere in the block (including targets and the `final:` list); that order is used by `sort state` and in reports. Output on success: `workflow ok: S states, T transitions` where T counts transition entries. Errors (the first one in line order is reported; the block is always consumed, and a failed definition leaves the previous one in place):

- `workflow: cannot redefine after issues were created` when any issue was ever created (checked before reading the block's lines);
- `workflow: bad state name 'X'`, `workflow: initial state defined twice`, `workflow: bad guard field 'X'`, `workflow: bad line 'LINE'` (LINE trimmed) for lines that fit no form or an entry with extra words;
- after all lines: `workflow: initial state missing`, then `workflow: 'S' is final and cannot have transitions` for the first (in line order) transition source that is final.

A workflow replaces the previous one. Commands other than `create` work without a workflow (no states exist).

## Commands

All fields below can be changed by `create`/`edit` with `field=value` tokens; the fields are `title`, `priority`, `assignee`, `points`, `due`, `labels`, `reporter`. `none` as a value clears `assignee`, `points`, `due`, `labels` and `reporter`; `labels` takes a comma list. Validation errors, in this order for a token: a token without `=` (or starting with it) is `expected field=value, got 'TOKEN'`; field `state` is `use move to change state`; any other unknown field is `unknown field 'F'`; then value errors: `empty title`, `bad priority 'V'`, `bad points 'V'`, `bad date 'V'`, `bad label 'L'` (L lowercased), `empty assignee`, `empty reporter`. Tokens are validated left to right; the first problem is reported. If a field is given more than once the last value wins.

- `actor NAME` prints `actor is NAME`. Usage error: `usage: actor NAME`.
- `today DATE` prints `today is DATE`; `bad date 'DATE'` or `usage: today DATE`.
- `create TITLE [field=value ...]`: the first token is the title. Errors: `no workflow defined` (first), `usage: create TITLE [field=value...]`, `empty title`, then field errors. The issue starts in the initial state with `reporter` = actor, clock +1, `created = updated = t`. Prints `created #ID`. Log entries (see *Audit log*): `created "TITLE"` then one entry per field whose given value differs from its default.
- `edit ID field=value ...`: errors in order: id errors, `#ID is in final state 'S'`, field errors, `usage: edit ID field=value...` when no field was given. Only fields whose value really changes count. If none changes: `#ID unchanged` (no clock change). Otherwise clock +1, `updated = t`, prints `updated #ID`, one log entry per changed field in the fixed order title, priority, assignee, points, due, labels, reporter, each `FIELD: OLD -> NEW` with `-` for an absent/empty value (labels are shown comma joined, no spaces).
- `label ID +a -b c`: add (`+` or no sign) or remove (`-`) labels, applied left to right to the issue's labels; then behaves exactly like `edit ID labels=...` (including the final-state error and the `unchanged` / `updated` output). Errors: `usage: label ID +label -label...`, `bad label 'L'`.
- `assign ID NAME` is `edit ID assignee=NAME` (`usage: assign ID NAME` when the token count is wrong).
- `move ID STATE [comment text...]` (words; the comment is the rest of the line after STATE verbatim). Checks in order: `usage: move ID STATE [comment...]`, id errors, `#ID is in final state 'S'`, `unknown state 'X'`, `already in state 'X'`, `transition 'A -> B' not allowed` (no such entry), and the guard `cannot move #ID to B: missing F1, F2` listing the unmet guard fields in the order written (a guard is unmet when the field is absent; `labels` unmet when empty; `reporter` unmet when cleared). On success clock +1, `state` and `updated = t`; log `state: A -> B`; if a comment was given it is appended to the comments (time t, current actor) and logged `comment: TEXT`. Prints `moved #ID: A -> B`.
- `comment ID TEXT...` (words; text is the rest after the id; also allowed on final issues): clock +1, `updated = t`, logs `comment: TEXT`, prints `commented #ID`. Usage: `usage: comment ID TEXT`.
- `delete ID`: removes the issue (any state); clock +1; logs `deleted` for it; prints `deleted #ID`. Usage: `usage: delete ID`. The log keeps the issue's earlier entries.
- `show ID` prints:

```
#ID TITLE
  state: S
  priority: P
  assignee: A
  points: N
  due: D
  labels: a, b
  reporter: R
  created: t=C, updated: t=U
  comments: K
    [t=T ACTOR] TEXT
```

with `-` for absent values (`labels: -` when empty) and one indented comment line per comment in order.

## Queries

`list QUERY` prints the matching issues, one per line, then a count line. The raw text is processed as follows. (1) If it ends with `limit N` (word `limit` preceded by whitespace or the start of the text, then a whitespace separated argument, at the end), that is the limit; N must be a valid integer (0 allowed) else `bad limit 'N'`. (2) In what remains, the first word `sort` (preceded by whitespace or at the start, followed by whitespace) starts the sort clause that runs to the end; the text before it is the filter. These keywords are recognised textually, even inside quotes. An empty filter matches every issue.

Filter syntax: terms combined with `AND`, `OR`, `NOT` and parentheses. `NOT` binds tighter than `AND`, which binds tighter than `OR`; two adjacent terms without an operator mean `AND`. A term is `FIELD OP VALUE` with no spaces around the operator; FIELD is lowercase letters and `_`, OP is one of `: != <= >= < > ~` (longest match), VALUE runs to whitespace or a parenthesis, or is a double quoted string (with the `\"` `\\` escapes; may contain spaces and parentheses). An unquoted value of an `:`, `!=` or `~` term containing `|` is a list of alternatives: the term holds if any alternative matches (for `!=` it is the negation of the `:` match). Quoted values are never split. Anything else (a bare word, a stray `)`) is `query: unexpected token 'TEXT'`; running out of tokens (`NOT` or `(` at the end, `AND` without right side) is `query: unexpected end of query`; an unterminated quote is `query: unterminated quote`. `AND`, `OR`, `NOT` are recognised only as exactly those uppercase words.

Fields (`ci` = case-insensitive):

| Field | Operators | Meaning |
| --- | --- | --- |
| `id` `created` `updated` | `: != < <= > >=` | integer comparison |
| `points` | same, plus `none` with `:`/`!=` | an issue without points matches only `none` (`:`) or `!=` of anything else; it never matches `<`, `<=`, `>`, `>=` |
| `title` `assignee` `reporter` | `: != ~` | `:` equals (ci); `~` substring (ci); an absent value equals only `none`; `!=` is the negation of `:`; `~` never matches an absent value |
| `text` | `~` | substring (ci) of the title or of any comment |
| `state` | `: !=` | exact state name; unknown names are `query: bad value 'V' for field 'state'` |
| `priority` | `: != < <= > >=` | ordered low < medium < high < critical (exact lowercase names); with ordering operators only a single value is allowed |
| `due` | `: != < <= > >=` | date string compare; `none` with `:`/`!=`; an absent due never matches ordering operators; ordering operators need a valid date value, `:`/`!=` accept a date or `none` |
| `label` or `labels` | `: != ~` | `:` the issue has that label (the value is lowercased); `none` matches issues without labels; `~` substring of any label; `!=` negates `:` |
| `is` | `:` | `open`, `final`, `overdue` (open, has a due date, due < today), `unassigned` |
| `has` | `:` | `assignee`, `due`, `points`, `labels`, `comments`, `reporter` |
| `view` | `:` | the filter of a saved view (its sort and limit are ignored here) |

Errors: `query: unknown field 'F'`; `query: bad operator 'OP' for field 'F'` (checked before values); `query: bad value 'V' for field 'F'` (for a list, the first bad alternative; for a multi value ordered comparison the whole text); `query: unknown view 'V'`. Integer values follow the integer rule above (so `points>-1` is a bad value).

Sort clause: fields separated by commas and/or spaces, each optionally prefixed by `-` for descending. Sort fields: `id created updated priority points state title assignee reporter due` (`state` by workflow order, `priority` by rank, `title`/`assignee`/`reporter` ci, `due` as text). Otherwise `bad sort field 'F'`. Absent values (`points`, `assignee`, `reporter`, `due`) sort after all present values ascending; descending is the exact reverse. Ties fall through to later fields and finally to ascending `id`. Without a sort clause the order is ascending id. Filter errors are reported before sort errors; the limit is applied last.

Issue line format: `#ID | STATE | PRIORITY | ASSIGNEE | POINTS | DUE | LABELS | TITLE` with `-` for absent values and labels joined by commas. The count line is `(1 issue)` or `(N issues)` (also for 0).

## Views

`view save NAME QUERY` (query as above, including optional `sort` and `limit`), `view run NAME [sort FIELDS] [limit N]`, `view list`, `view show NAME`, `view delete NAME`. Other subcommands or missing arguments: `usage: view save|run|list|show|delete` (with a specific `usage: view save NAME QUERY`, `usage: view run NAME [sort FIELDS] [limit N]`, `usage: view show NAME`, `usage: view delete NAME` for a known subcommand with wrong arguments).

- `save`: NAME matches `[a-z][a-z0-9_-]*` (`bad view name 'N'`). The query is validated fully (filter, sort fields, limit; views it references must exist) then stored verbatim (trimmed). Saving over an existing name replaces it. A view that would directly or indirectly reference itself: `view 'N' would reference itself`. Prints `saved view NAME`.
- `run`: runs the stored query. Extra `sort`/`limit` clauses replace the stored ones; any extra filter text is `unexpected 'TEXT'`. Unknown name: `unknown view 'N'`. Output like `list`.
- `list`: `NAME: QUERY` lines in name order, or `(no views)`. `show` prints one such line.
- `delete`: refused while another view uses it: `view 'N' is used by 'M'` (M the first user in name order); otherwise `deleted view N`.

Views are re-evaluated on every use against current data.

## bulk

`bulk ACTION... where QUERY`: the text is split at the first word `where` (usage: `usage: bulk ACTION... where QUERY`). ACTION tokens: `move STATE`, `assign NAME`, `label +a -b`, `set field=value...`; unknown: `unknown bulk action 'X'`; wrong shape: `usage: bulk move STATE where QUERY`, `usage: bulk assign NAME where QUERY`, `usage: bulk label +label... where QUERY`, `usage: bulk set field=value... where QUERY`. QUERY is a plain filter (no sort/limit; an empty one matches everything), evaluated once before any change. The matching issues are processed in ascending id order, each exactly as the corresponding single command would (printing its normal output line); a failure prints `#ID error: MESSAGE` and processing continues. Finally `bulk: N ok, M failed` (an `unchanged` result counts as ok). A query or action error aborts before any change as a normal `error:` line.

## Audit log

Every change adds entries `t=T ACTOR #ID DETAIL` (the clock value and actor at the time). Entries of one command share the same `t`. `log` prints all entries in order, `log ID` only those of one issue (allowed for deleted issues, but the id must have been issued: `no such issue #N`), `log tail N` / `log ID tail N` the last N of the selection (N integer, else `bad tail 'X'`); `(no log entries)` when empty. Usage: `usage: log [ID] [tail N]`.

## Reports

- `report summary`:

```
issues: TOTAL (open O, final F)
by state:
  NAME: COUNT        (every workflow state in order)
by priority:
  critical: N        (critical, high, medium, low)
unassigned: N
overdue: N
open points: N
```

`unassigned`, `overdue` (due before today) and `open points` (sum of points) are over open issues only.
- `report workload`: over open issues, one line `NAME: N issue(s), P points` per assignee (grouped case-insensitively, displayed with the first spelling in id order; `issue` when N is 1), ordered by points descending, then count descending, then name (ci); an `unassigned` line comes last when any open issue has no assignee. `(no open issues)` when none.
- `report labels [FILTER]`: label counts over the issues matching the filter (default all, no sort/limit), as `label: N`, by count descending then name; `(no labels)` if none.
- `report timeline ID`: one line per state period: `STATE: t=FROM..TO (DURATION)`. The first period starts at `created` in the initial state; each logged state change starts a new one; the last ends at the current clock value. Usage: `usage: report timeline ID`; general: `usage: report summary|workload|labels|timeline`.
