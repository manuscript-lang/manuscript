+++
title = "Diagnostic catalogue"
weight = 9
+++

# Diagnostic catalogue

Every message that reaches an author or an agent states the cause, the location, and a concrete fix, in the shape `<cause>; <fix>` (see [diagnostics](../developer-tooling/source/diagnostics.md)). This page records which message families were reviewed and the rule each follows. When adding a message, follow the same shape and extend the matching test in `pkg/checker/hints_test.go`, `pkg/parser/hints_test.go`, or `internal/cli/cli_test.go`.

## Lexing and layout (`pkg/lexer`)

| Situation | Message names |
| --- | --- |
| Tab, odd indentation, missing `:` before an indented line, bad dedent | The measured indentation and the expected one; a line that indents without a preceding `:` says the previous line must end with `:`. |
| Unterminated or mismatched `(`, `[`, `{` | The opener's line and column and the closer to add. |
| Unterminated text, bad escape, bad interpolation | The escapes that are valid, `\{` for a literal brace, and the single-line rule. |
| Foreign punctuation (`;`, `'`, `!`, `\|`, `?`, backtick) | The Manuscript spelling (end the line, double quotes, `not`, `or`, `Optional`/`try`). |
| Numeric literal errors | The valid form (`42`, `1e3`, `1.5d`). |

## Parsing (`pkg/parser`)

Unexpected tokens are described in source terms (`end of line`, `name 'x'`, `'case'`) instead of internal token kinds. Missing `:`, `->`, closing brackets, and `from` carry the usual fix. Statements at top level, standalone non-call expressions, comparison chains, `case` inside `match` each say what to write instead.

Compound assignment (`+=`, `-=`, `*=`, `/=`, `%=`) points at the full operator and suggests an explicit assignment. String-literal match patterns explain that arms select alternative cases or concrete types and suggest `if`/`else` string comparisons. Wildcard imports explain that namespace imports are unsupported and show named imports.

## Names, calls, and types (`pkg/checker`)

| Message | Fix included |
| --- | --- |
| `unknown binding`, `unknown type` | Nearest declared name, else the standard module to import, else how to declare it. |
| `module does not export` | Nearest export, else the module's declared export list without implicit prelude or imported symbols, plus named-import guidance; private names say to add `export`. |
| `redundant prelude import` (`MS2003`) | Remove the canonical prelude binding from the import and use its ambient declaration; the machine fix preserves neighboring bindings and comments. |
| `unknown or ambiguous member` | Nearest field or operation, else the available ones. |
| `missing argument`, `unknown argument`, `duplicate argument` | The parameter and its type at the call site; the parameter list. |
| `too many positional arguments` | Every parameter is already supplied; remove the excess argument. |
| `callee is not a function` | The callee name and its type. |
| `non-exhaustive match`, `unknown case`, payload arity | Missing cases, the case list, the binding count. |
| `cannot assign immutable binding`, captured binding | `var` instead of `let`; how to carry state out of a closure. |
| Operator operand mismatch | Both operand types, in one diagnostic rather than a chain. |
| Interface implementations | The missing or extra operation with its expected signature. |
| `expected X, found Y` | Unchanged; the position is the expression. |

## Modules, projects, and builds (`pkg/frontend`, `pkg/project`, `pkg/compiler`, `pkg/build`)

Missing files and modules name the path searched. Manifest errors include the `ms.toml` line and the corrected form. Import alias errors list declared aliases. A wrong entry point says which of missing, private, generic, parameterized, or non-`Int` `main` applies and is reported at that declaration. Lock, cache, toolchain, and Go-build failures say how to regenerate the lock, which environment variable selects a toolchain, and when to report a compiler bug.

## Command line (`internal/cli`)

Unknown commands suggest the nearest one and list the rest. Missing arguments, invalid flags, and flags used with the wrong command name the flag and the commands that accept it. A diagnostic run ends with an error count.

## Runtime faults (`pkg/runtime`)

User-reachable faults (division by zero, Int overflow, `Optional.unwrap` on none, index and slice bounds, destructuring length, byte range, queue capacity, closed guards and groups, exit code range) state the valid range or the safer alternative. Internal invariant faults are unchanged.
