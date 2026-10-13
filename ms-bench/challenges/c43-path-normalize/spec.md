# Path toolkit

Implement a small set of purely lexical path operations (no file system access) on Unix-style paths. Input is
a script, one command per line; each non-blank line produces exactly one line of output. Tokens are separated
by runs of spaces or tabs, so paths never contain whitespace and are never empty. Blank lines produce no
output.

A line whose first token is not a command below, or with the wrong number of arguments for its command, prints
`error: bad command`.

## Normal form

A path is *absolute* if it starts with `/`, otherwise *relative*. To **clean** a path:

1. Split it at `/` and ignore empty segments (so repeated slashes collapse, and trailing slashes vanish; a
   leading `//` is just the root).
2. Process the segments left to right with a stack:
   - `.` is dropped;
   - `..` removes the top of the stack when the stack is non-empty and its top is not `..`; otherwise, for an
     absolute path the `..` is dropped (the parent of the root is the root), and for a relative path the `..`
     is pushed;
   - any other segment is pushed.
3. The result is the stack joined with `/`, prefixed with `/` when the path is absolute. An absolute path with
   an empty stack is `/`; a relative path with an empty stack is `.`.

The *components* of a cleaned path are its stack entries, and I write `abs` for whether it is absolute.
"Printing" components means the form in step 3.

## Commands

| command | result |
| --- | --- |
| `clean P` | `P` cleaned |
| `join P1 P2 ...` (one or more arguments) | the arguments joined with `/` between them, then cleaned (so a later absolute argument does **not** reset the path) |
| `resolve CWD P` | if `CWD` is not absolute: `error: cwd not absolute` (checked first). Otherwise `P` cleaned if `P` is absolute, else `CWD/P` cleaned |
| `rel BASE TARGET` | the relative path that leads from cleaned `BASE` to cleaned `TARGET` (below) |
| `base P` | last element of `P` (below) |
| `dir P` | everything but the last element of `P` (below) |
| `ext P` | extension of the last element of `P`, or `(none)` |
| `common P1 P2 ...` (one or more arguments) | the longest common ancestor of the cleaned paths (below) |

### `rel`

Clean both paths. If one is absolute and the other relative, print `error: cannot relativize`. Strip the longest
common prefix of components from both. If the remaining components of `BASE` contain a `..`, print
`error: cannot relativize`. Otherwise the answer is one `..` for each remaining component of `BASE`, followed by
the remaining components of `TARGET`, joined with `/`; if that is empty the answer is `.`. The result is
always relative. For example `rel /a/b /a/c/d` is `../c/d`, `rel a ../b` is `../../b`, and `rel ../a b` is an
error.

### `base`, `dir`, `ext`

These work on the raw token, not the cleaned one.

- `base P`: remove all trailing `/` from `P`. If nothing is left (`P` was all slashes), the answer is `/`.
  Otherwise the answer is the text after the last `/` of what is left (the whole thing if it has no `/`).
  Note that `base .` is `.` and `base a/..` is `..`.
- `dir P`: find the last `/` in `P`. If there is none the answer is `.`. Otherwise clean the text up to and
  including that `/` (`dir a/b/` is `a/b`, `dir /a` is `/`, `dir a//b` is `a`).
- `ext P`: let `b` be `base P`. If `b` has a `.` at some index greater than 0, the answer is the text from the
  last such `.` to the end of `b` (`a.tar.gz` gives `.gz`; `a.` gives `.`; `..` gives `.`). Otherwise
  `(none)`; in particular a name that only has a leading dot, like `.bashrc`, has no extension.

### `common`

Clean every argument. If they are not all absolute or all relative, print `error: mixed`. Otherwise strip to the
longest prefix of components shared by every argument and print it (`/` for an absolute path with no shared
components, `.` for a relative one). `..` components are ordinary components here. With one argument the
answer is that argument cleaned.

## Example

Input:

    clean /a/./b/../c//d/
    clean ../x/../../y
    join a b/../c /d
    resolve /home/me ../you/./f.txt
    rel /a/b /a/c/d
    base /a/b.tar.gz
    dir /a/b/
    ext /a/b.tar.gz
    common /a/b/c /a/b/d /a/e
    frob

Output:

    /a/c/d
    ../../y
    a/c/d
    /home/you/f.txt
    ../c/d
    b.tar.gz
    /a/b
    .gz
    /a
    error: bad command
