[Wiki](../index.md) › [Tooling and docs](index.md)

# Diagnostics are `<cause>; <fix>`, and tools key on the cause

Verified: agents act on a diagnostic only when it names the cause, the location, and a concrete fix (nearest name, import line, valid options). Messages therefore read `<cause>; <fix>`. A diagnostic's rule code classifies only the text before the first `; `, so fix text cannot change a rule code. Partial parsing recovers from an unterminated delimiter by matching the message prefix, and the lexer reports it at end of file; moving that position or exact wording breaks editor recovery.

Verified: the forgiving editor scanner must consume a rejected Unicode character as one scalar. Byte-sized tokens can publish a diagnostic ending inside a UTF-16 surrogate pair. Server coordinate regressions check complete ranges and round-trip their endpoints with LF/CRLF.

Verified: a byte scanner can have consumed only the first byte of a rejected Unicode character. Report its start rather than that cursor: diagnostic offsets must remain UTF-8 boundaries, including nested literals and CRLF source. Lexer span regressions cover bidi text controls and non-ASCII Unicode-escape digits.

Verified: replacing a symbolic operator with a word must preserve token boundaries.
An edit of `left&&right` to `leftandright` parses as one name instead of a logical
expression. Add spaces only where the replacement would join an adjacent word;
retain existing whitespace and delimiters. Logical-fix regressions
apply the actual edits to direct and nested interpolated expressions with LF/CRLF,
then check the parsed operator and formatter idempotence.

A diagnostic file that is already absolute is printed as itself. `finding_terminal_text` used to prefix the source root onto every file, so a missing `/tmp/missing.ms` whose root was `/tmp` displayed as `/tmp//tmp/missing.ms`. A relative file still sits under the root; a package file (`@id/...`) does not. `findings_unit` covers all three.

An empty list is a null pointer. Adding zero to it (`ptr + 0`) is undefined, and UBSan rejects it. Sort, scan, or describe the list only when it has elements (`finding_add_graph` on a graph with no diagnostics, an empty `.gitignore`, a type with no arguments).

Apply when: adding or rewording any lexer, parser, checker, project, compiler, CLI, or runtime message.
Evidence: [message-shape rule](../../../documentation/developer-tooling/source/diagnostics.md), code classification, checker hints, recovery.
Verify: run `ctest --preset ci` and `make conform` (check-phase fixtures compare code, phase, message, and position); extend the hint tests with the new message.

Project import hints must recognize every current exported declaration spelling,
including `export enum` and generic enums. Keep the header fast path and parsed
recovery path aligned, with enum-shaped text/comment lookalikes excluded by lexer
positions; test the machine-applicable import fix as well as name collection.

A `fix` must be tested by applying it. a corpus-fix test (`src/cli/check_fix.c`, run by `ctest`) runs `ms check --only types --fix` over one corpus fixture per kind of fix (about 2 s; all 263 took 11 s and pushed linux-amd64 over the 600 s budget) and requires the fixed diagnostic gone and no new syntax error. It found `var fn` inserted three bytes before the method name (wrong for `fn Type.name`, so the position is now recorded by the parser) and `:` appended to a header that already had an inline body. Errors that only appear after a fix are usually unmasked, not caused by it; judge only syntax and the fixed diagnostic.

Lesson (agent-mistake bash, 2026-11-18): probing about 100 realistic wrong programs found the misleading cases are mostly where the checker reports a *symptom* of a habit from another language. Each now names the cause: a bare field name inside a method says `self.name` (and fixes it); `error("text")` says wrap it in `Error(...)` (and fixes it); `x => x * 2` is rewritten to `x => x * 2`; `promise(fn: 1)` says the entry must return a Result instead of reporting a generic-inference conflict; a braced block's fix now removes the spaces before `:` and the stray closing `}`; an import from a nonexistent module names the module that really exports the imported name unless the spelling guess exports it. A diagnostic that already explains a failed callback must also suppress the follow-on "cannot infer" and `<invalid>` mismatch lines, or the agent chases the noise.

Lesson (manifest and project errors, 2026-11-19): a manifest key is checked for being known before its value's type, or `retries = 3` reads "must be a string"; a path that `ms.toml` names and that does not exist says the path comes from ms.toml, not "pass a .ms file". A type parameter the other arguments have not fixed prints as `_` in a missing-argument message, never `<invalid>`. Multi-file `--fix` was checked end to end (import fixes in the importing file, conversion fixes in the dependency) and held.

## Generic shapes, import cycles and quick-fix ranges (2026-11-19)

- A wrong-shaped argument to a generic parameter (`List[T]` given an `Int`) is a mismatch, not "conflicting generic inference", and it suppresses the follow-on "cannot infer" error. Only two arguments disagreeing about one variable is a conflict.
- A cycle error names the whole path (`a.ms -> b.ms -> a.ms`), not one module.
- An LSP quick-fix pairs with the range the diagnostic is published with (`text::diagnostic_range`), not the fix's own range. A fix that edits another place, such as the `x := 1` declaration for an assignment, was otherwise dropped for a request at the diagnostic.
