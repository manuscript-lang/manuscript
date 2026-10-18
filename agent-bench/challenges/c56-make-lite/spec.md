# make-lite

Implement a simulator of a small `make`-like build tool. It reads a Makefile, a table of existing files with modification times, and a list of requests. It never runs real commands and never touches the real file system: building a target prints the commands that would run and updates the in-memory file table, so later requests see the effects. The program always exits with status 0; every error is printed on stdout.

## Input

Standard input has three sections separated by lines that consist of exactly `====` (only the first two such lines are separators; later ones belong to the request section). Line endings may be `\n` or `\r\n`.

1. The Makefile text.
2. The file table: one file per line, `NAME MTIME` (two whitespace-separated fields, MTIME a non-negative integer). Lines that do not have exactly two fields are ignored. Files here "exist".
3. Requests, one per line. Blank lines and lines whose first non-blank character is `#` are ignored.

A *clock* starts at the largest mtime in the table (0 if the table is empty) and is shared by all requests. Every time the clock is used it is first incremented ("`++clock`") and the new value is the timestamp.

## Output framing

For every request, first print `> ` followed by the request line with trailing whitespace removed, then the output of the request.

## Requests

Every `build`, `dry`, `deps` and `targets` request behaves like a fresh invocation of make: the Makefile is parsed again from scratch (so parse-time output such as `$(info ...)`, warnings and fatal errors appear again for each such request), using the file table as it is at that moment.

Arguments of the form `NAME=VALUE` (the `=` not in first position; VALUE has no spaces and may be empty) on these four requests are *command-line variables*. They define variables that take precedence over any assignment in the Makefile (assignments of the same name in the Makefile, with any operator, are ignored). Their values are recursively expanded variables (flavor below). Every other argument is a target name.

- `build [VAR=VALUE...] [TARGET...]`: build the goals in order. With no goals, build the default goal. If there is no default goal print `make: *** No targets.  Stop.`
- `dry [VAR=VALUE...] [TARGET...]`: like `build` but only print what would be done (see Dry run).
- `deps [VAR=VALUE...] TARGET`: print the transitive prerequisites of TARGET (below). Without exactly one target print `usage: deps TARGET`.
- `targets [VAR=VALUE...]`: print the rules (below).
- `expand TEXT`: the rest of the line after `expand`, with leading and trailing whitespace removed, is expanded using the parsed Makefile (no command-line variables, no automatic variables) and printed as `[RESULT]`.
- `files`: print every file as `NAME MTIME`, sorted by name (byte order), or `(no files)`.
- `touch FILE`: set the file's mtime to `++clock` (creating it). `touch FILE N`: set it to the integer N exactly (creating it) and raise the clock to at least N. Anything else (wrong argument count, non-integer N) prints `bad request`. Prints nothing on success.
- `rm FILE...`: remove the files from the table (missing files are ignored). Prints nothing.
- Anything else prints `unknown request: WORD`.

`files`, `touch`, `rm` do not parse the Makefile.

If parsing the Makefile fails with a fatal error, the error line is printed and the request ends (the rest of the request does nothing).

## Makefile syntax

### Logical lines

1. Physical line numbers start at 1. A physical line ending in `\` is joined to the next one: the `\` and any whitespace before it are removed, a single space is inserted, and the leading whitespace of the next line is removed (repeatable). The logical line's number is the number of its first physical line.
2. A logical line that starts with a TAB character is a *recipe line*. Otherwise any `#` starts a comment that runs to the end of the line, except that `\#` stands for a literal `#`. Recipe lines are not comment-stripped (a `#` stays part of the command).
3. Lines that are empty or only whitespace (after comment removal; for recipe lines after the TAB) are ignored; they do not end a rule. The text of a recipe line is the line with all leading TABs removed.
4. Leading and trailing spaces/tabs of non-recipe lines are removed.

### Conditionals

Lines (not recipe lines) whose first word is one of these directives:

- `ifdef NAME` / `ifndef NAME`: NAME is expanded and trimmed; the variable counts as defined only if it exists and its stored (unexpanded) value is not empty.
- `ifeq (A,B)` / `ifneq (A,B)`: exactly one top-level comma inside the parentheses; each side is trimmed, expanded, trimmed again, and compared as strings. Any other form is the fatal error `invalid syntax in conditional`.
- `else`: switches to the other branch (only the plain `else`). A second `else` in one block, or one without an open block, is `extraneous 'else'`.
- `endif`: closes the innermost block. With no open block: `extraneous 'endif'`.
- At the end of the file, any unclosed block is the fatal error `missing 'endif'` reported with the line number of the innermost unclosed `if...`.

Conditionals nest. Lines in an inactive branch are skipped completely (but nested directives are still tracked). Conditional arguments are expanded as at parse time (they see the variables defined so far).

### Assignments

Let `eq` be the index of the first `=` in the logical line and `col` the index of the first `:` that is outside any `$(...)`/`${...}` reference (and before any `;`), if there is one. The line is an assignment if `eq` exists and either there is no `col`, or `col > eq`, or `col == eq-1` (the `:=` case).

Forms (the operator is `=`, or `:=`, `?=`, `+=` when `eq-1` holds `:`, `?`, `+`). The name is the text before the operator, expanded and trimmed; an empty name is the fatal error `empty variable name`. The value is the text after `=` with leading and trailing whitespace removed.

- `NAME = value`: recursive flavor; stored unexpanded, expanded each time it is referenced.
- `NAME := value`: simple flavor; expanded immediately.
- `NAME ?= value`: like `=` but only if NAME is not defined at all.
- `NAME += value`: if undefined, like `=`. If NAME is simple: expand value now and append to the old value separated by one space (no space if either side is empty); the result stays simple. If recursive: append the unexpanded value (separated by one space unless either side is empty); it stays recursive.

Assignments to names given on the command line are ignored.

### Rules

If a logical line is not an assignment and has a top-level `:` it is a rule `TARGETS : PREREQS`, optionally followed by `; COMMAND` (the text after the first `;` after the colon is a recipe line for this rule). Targets and prerequisites are expanded immediately (parse time, no automatic variables) and split on whitespace; in the expanded prerequisite text, everything after the first `|` is *order-only* prerequisites.

Subsequent recipe lines (until the next non-recipe, non-blank logical line) belong to that rule. A recipe line with no open rule is the fatal error `recipe commences before first target`. A non-recipe line closes the open rule (assignments and conditionals close it too).

- The rule `.PHONY: names` (targets exactly `.PHONY`) marks the prerequisites phony; it has no other effect.
- A target containing `%` defines a *pattern rule* (one `%`; it stands for a non-empty stem). Each pattern rule is stored separately in file order. A pattern rule without recipe lines is only listed by `targets`; it is never used for building.
- Any other target is an explicit rule. Rules for the same target accumulate: normal prerequisites and order-only prerequisites are appended in order. If a later rule for a target provides recipe lines and an earlier rule already had recipe lines, the new recipe replaces the old one and the line `Makefile:N: warning: overriding recipe for target 'T'` is printed (N is the line number of the rule line with the new recipe) when that rule ends. A rule with several targets gives each target the same prerequisites and the same recipe lines.
- The *default goal* is the first explicit target, in order of first appearance as a rule target, whose name does not start with `.`.

Any other line (not blank after expansion) is the fatal error `missing separator`. A line that expands to only whitespace is accepted and ignored (this is how a bare `$(info text)` line works).

## Expansion

`$` introduces a reference. `$$` is a literal `$`. `$(...)` and `${...}` enclose a reference or function call; nested brackets of the same kind inside are balanced (a missing closer is the fatal error `unterminated variable reference`). `$X` with any single other character X is the variable named X (so `$@`, `$<`, `$^`, `$?`, `$*`, `$|`, `$A`). A lone `$` at the end of the text is dropped.

Inside the brackets:

- If the text starts with a function name followed by a space or tab, it is a function call.
- Otherwise the text is first expanded, then used as a variable name (surrounding whitespace removed). An undefined variable expands to the empty string. If the name text contains `:` (not in first position) followed later by `=`, it is a *substitution reference* `VAR:FROM=TO`: the value of VAR is word-by-word transformed with `patsubst`, where, if FROM has no `%`, it is treated as `%FROM` and TO as `%TO`.

A recursive variable that (directly or indirectly) references itself during expansion is the fatal error `Recursive variable 'NAME' references itself (eventually)`.

Fatal errors are printed as `Makefile:N: *** MESSAGE.  Stop.` where N is the number of the logical line being processed (parse time or while expanding a recipe line), and `make: *** MESSAGE.  Stop.` when no line is current.

### Functions

Arguments are split at commas outside nested brackets (parentheses and braces both count). Each raw argument is trimmed of spaces/tabs, THEN expanded (so a variable holding a space can be used as an argument). Missing arguments are empty; extra arguments are ignored. "Words" are separated by runs of spaces/tabs/newlines; results join words with a single space.

- `subst(from,to,text)`: replace every non-overlapping occurrence of `from` (left to right); empty `from` returns `text` unchanged.
- `patsubst(pattern,replacement,text)`: for each word: if it matches `pattern` (which may contain one `%` matching any stem, possibly empty here; without `%` it must match exactly) replace it by `replacement` (its first `%` replaced by the stem); other words are kept.
- `strip(text)`: collapse whitespace runs and trim.
- `findstring(find,text)`: `find` if it occurs in `text`, else empty.
- `filter(patterns,words)`, `filter-out(patterns,words)`: keep/drop words matching any of the `%` patterns.
- `sort(words)`: sort in byte order and remove duplicates.
- `word(n,text)`: the n-th word (1-based); empty if n is out of range or not a positive integer. `wordlist(s,e,text)`: words s..e inclusive; empty if s<1, e<s, or s is past the end; e is clamped. `words(text)`: count. `firstword`, `lastword`.
- `dir`, `notdir`, `suffix`, `basename` per word: `dir` gives everything up to and including the last `/` (`./` if none); `notdir` the part after the last `/`; `suffix` the extension of the last component including the dot (omitted if none); `basename` the word without that extension (unchanged if none).
- `addprefix(prefix,words)`, `addsuffix(suffix,words)`.
- `wildcard(patterns)`: for each whitespace-separated pattern, in order, the existing files (current table) matching it, sorted in byte order. `*` matches any run of non-`/` characters, `?` one non-`/` character, other characters literally; a pattern without wildcard characters matches the file of exactly that name if it exists.
- `foreach(var,list,text)`: expand `list`, and for each word expand `text` with variable `var` (a name, expanded) bound to the word; results joined by a single space (empty results included as empty items). The binding takes precedence over every other variable.
- `if(cond,then[,else])`: expand `cond`; if its trimmed result is non-empty expand and return `then`, else expand and return `else` (empty if missing). Only the chosen branch is expanded.
- `info(text)`: expands `text`, prints it on its own line immediately, and returns empty.
- `error(text)`: fatal error with the expanded text as the message.

Any other name followed by a space is not a function; the whole text is treated as a variable name.

### Automatic variables

Available only while expanding recipe lines of a rule being run (empty elsewhere):

- `$@` the target; `$<` the first prerequisite of the resolved rule (the first element of the list before de-duplication, normal prerequisites only); `$^` all normal prerequisites with duplicates removed (first occurrence kept); `$?` those of `$^` for which the target did not exist before this rule ran, or which were rebuilt/changed during this request, or whose mtime is greater than the target's mtime; `$|` the order-only prerequisites (de-duplicated); `$*` the stem of the pattern rule used (empty for explicit rules).

## Rule resolution

For a target T, the *resolved rule* is:

1. If an explicit rule for T has recipe lines: that rule (its prerequisites, order-only prerequisites, recipe).
2. Otherwise find the first pattern rule (file order, only rules with recipe lines) whose pattern matches T with a non-empty stem and for which every prerequisite and order-only prerequisite, after replacing the first `%` by the stem, *can be made*: the name is in the file table, or has an explicit rule, or is phony, or (recursively, to a depth of 8 levels) some pattern rule would be found for it. If found: prerequisites are the pattern rule's (stem-substituted) prerequisites followed by the explicit rule's prerequisites (if T has an explicit rule without recipe); order-only likewise; the recipe and stem come from the pattern rule.
3. Otherwise, if T has an explicit rule without recipe: its prerequisites with no recipe.
4. Otherwise T has no rule.

## Building

A build request keeps a memo of the targets already processed in this request. `update(T, neededBy)` returns whether T *changed*:

1. If T was already processed, return its stored result.
2. If T is already on the current dependency stack, print `make: *** Circular dependency detected: A -> B -> ... -> T.  Stop.` (the cycle starting from the earlier occurrence of T) and abort the whole request.
3. Resolve T. If it has no rule: if T is in the file table, it is up to date (unchanged); else if T is phony it counts as changed; else abort the request with `make: *** No rule to make target 'T', needed by 'N'.  Stop.` (or `make: *** No rule to make target 'T'.  Stop.` when T is a goal).
4. Remember whether T was in the table and its mtime. Process the de-duplicated normal prerequisites in order with `update(P, T)`, noting whether any returned changed and whether any prerequisite present in the table has a larger mtime than T's remembered mtime (checked only if T was in the table). Then process the de-duplicated order-only prerequisites (their results are ignored).
5. T must be rebuilt if it is phony, or not in the table now, or some normal prerequisite changed, or some prerequisite is newer as described. If so T *changed*; and if the resolved rule has a recipe, run it (below).
6. Store the result and return it.

After each goal of a `build`/`dry` request, if no recipe was run since that goal started, print `make: 'G' is up to date.` when the goal's resolved rule has a recipe or the goal is a non-phony file in the table; otherwise print `make: Nothing to be done for 'G'.`

### Running a recipe

Each recipe line is expanded (with automatic variables; the current line number is that of the recipe line) then trimmed. Leading `@`, `-` and `+` characters (with optional spaces between) are prefixes: `@` suppresses echoing, `-` ignores a failure, `+` has no effect. The remaining text is the command. Unless silenced, print the command. Then it is simulated by its first word (words separated by whitespace):

- `false`: fails with status 1. `exit [N]`: status N (default 0; a non-integer N is status 2).
- `touch FILE...`: each non-option word (not starting with `-`) is set to `++clock`.
- `rm [-f] FILE...`: removes the non-option files from the table.
- `cp SRC DST` (exactly two words): if SRC is not in the table print `cp: cannot stat 'SRC': No such file or directory` and fail with status 1, else set DST to `++clock`.
- `echo ARGS...`: print the arguments with every `'` and `"` character removed, joined by single spaces.
- Anything else does nothing and succeeds.

A failing command that is not ignored prints `make: *** [Makefile:L: T] Error N` (L the recipe line's number, T the target) and aborts the whole request. An ignored failure prints `make: [Makefile:L: T] Error N (ignored)` and continues.

When all lines have run, if T is not phony its mtime becomes `++clock` (even if the recipe touched or removed it).

### Dry run

`dry` builds exactly like `build` (same order, same decisions, same messages and fatal errors) except that recipe lines are printed (with prefixes removed, including `@` lines) and never simulated: no command can fail, no file or clock changes, no `echo` output, and the target's mtime is not updated. A target "built" by the dry run still counts as changed for its dependents.

## `deps`

Print the prerequisites (normal first, then order-only, de-duplicated within each list) of the resolved rule of the target, recursively, in depth-first post-order (a prerequisite's own prerequisites are printed before it), each name once, one per line, not including the target itself. If there are none print `(no prerequisites)`. A cycle prints the same `Circular dependency detected` error line as building (and nothing else for the request). Targets with no rule are listed like any other name.

## `targets`

Prints, in this order: `default: NAME` if there is a default goal; then each explicit target in order of first appearance as `NAME: P1 P2 | O1 O2` (the `: ` followed by normal prerequisites separated by spaces, then ` | ` and the order-only ones; a target without prerequisites is just `NAME:`); then each pattern rule in file order as `pattern PAT: P1 P2 | O1`, in the same format; then, if any phony names were declared, `phony: ` followed by the names in order of first declaration.

## Output summary

All output is on stdout; the exit status is always 0. Output is compared exactly (trailing whitespace per line is ignored by the checker).
