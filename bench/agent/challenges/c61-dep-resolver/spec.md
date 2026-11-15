# dep-resolver

Implement a package dependency resolver. A script of commands arrives on standard input, one per line; blank lines (empty or only whitespace) are ignored. A line is split on runs of whitespace into tokens, and the first token is the command name (case-sensitive). Every error is a line `error: MESSAGE` on standard output; the program exits with status 0.

## Definitions

- A **name** is one or more characters from `a-z`, `0-9` and `-`.
- A **version** is `MAJOR.MINOR.PATCH`: three numbers separated by dots. A number is 1 to 6 ASCII digits with no leading zero (`0` alone is fine). Versions compare by MAJOR, then MINOR, then PATCH, numerically. Output prints them the way they were written (which is always the canonical form).
- A **constraint** is one or more *clauses* separated by commas (no spaces). A version satisfies the constraint when it satisfies every clause. A clause is one of:
  - `*`: every version.
  - `=V`, `>V`, `>=V`, `<V`, `<=V` where V is a version. A bare version `V` with no operator means `=V`.
  - `^V` (compatible): at least V and below the next breaking version: `^1.2.3` is `>=1.2.3` and `<2.0.0`; if MAJOR is 0, `^0.2.3` is `>=0.2.3` and `<0.3.0`; if MAJOR and MINOR are both 0, `^0.0.3` is `>=0.0.3` and `<0.0.4`.
  - `~V` (patch updates): at least V and below the next minor version: `~1.2.3` is `>=1.2.3` and `<1.3.0`.
  - An empty clause (such as `>=1.0.0,` or an empty constraint) or any other text is not a constraint.

## Commands

- `pkg NAME VERSION [DEP ...]` (at least 3 tokens, else `error: usage`): adds a release of package NAME. Each DEP is `NAME:CONSTRAINT`. Checks in this order, the first failure prints its error and changes nothing: `error: bad name 'NAME'`; `error: bad version 'VERSION'`; then each DEP in the order given: `error: bad dependency 'TOKEN'` (no colon, or the name part is not a name), `error: bad constraint 'CONSTRAINT'` (the text after the first colon, as written), `error: duplicate dependency 'NAME'` (a name already used by an earlier DEP of this release); finally `error: duplicate NAME VERSION` if that release exists. Otherwise prints `ok`. A release may depend on packages that do not exist yet.
- `list NAME` (exactly 2 tokens, else `error: usage`): `error: unknown package NAME` if no release of NAME was added, else one line `NAME: V1 V2 ...` with all its versions in ascending order separated by single spaces.
- `resolve NAME CONSTRAINT` (exactly 3 tokens, else `error: usage`): chooses one version for NAME and for every package it needs, transitively. `error: bad constraint 'CONSTRAINT'` if the constraint is malformed. The search below decides the result.
- Any other command name: `error: unknown command`.

## The search

The search is a depth-first search with backtracking that must be followed exactly, because several valid solutions can exist and the output must be the one this procedure finds.

`solve(pending)`, where `pending` is a list of (name, constraint) requirements, and a table `chosen` of name to version that starts empty:

1. If `pending` is empty, the search succeeded.
2. Take the first requirement (N, C); the rest of the list is `rest`.
3. If N is already in `chosen`: the search continues with `rest` only when the chosen version satisfies C; otherwise this branch fails.
4. If no release of N exists at all: the whole `resolve` stops at once with `error: unknown package N` (no backtracking).
5. Otherwise try the releases of N that satisfy C from the highest version to the lowest. For each: put it in `chosen`, then run `solve` on this release's dependencies (sorted by dependency name in byte order, each with its constraint) followed by `rest`. If that succeeds, the search succeeded. If not, remove N from `chosen` and try the next release.
6. If no release works, this branch fails.

`resolve NAME CONSTRAINT` starts with `pending = [(NAME, CONSTRAINT)]`. On success it prints `resolved K`, where K is the number of chosen packages, then one line `NAME VERSION` per chosen package sorted by name in byte order (the root is included). If the search fails and no unknown package stopped it: `error: cannot resolve NAME CONSTRAINT` (as written in the command). Dependency cycles are fine: a package already in `chosen` is only checked against the constraint.

## Example

    pkg a 1.0.0 b:^1.0.0 c:>=1.0.0,<3.0.0
    pkg b 1.2.0 c:^2.0.0
    pkg b 1.0.0
    pkg c 2.5.1
    pkg c 3.1.0
    resolve a *
    list b
    resolve a =9.9.9
    resolve z *

Output:

    ok
    ok
    ok
    ok
    ok
    resolved 3
    a 1.0.0
    b 1.2.0
    c 2.5.1
    b: 1.0.0 1.2.0
    error: cannot resolve a =9.9.9
    error: unknown package z
