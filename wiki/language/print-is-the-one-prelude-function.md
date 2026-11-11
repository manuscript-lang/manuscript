[Wiki](../index.md) › [Language](index.md)

# `print` is the one prelude function

Decision: Chinmay asked for a `print` function (2026-11-03) after a Ruby comparison found hello world needed `stdout().write(...)?`. `print(value)` is in the prelude: any value as text (the `to_string()` representation) plus a newline, never fails, buffered like `stdout()`. It is a deliberate exception to [methods before free functions](methods-before-free-functions.md): there is no receiver. `println`, `printf`, `puts` and `echo` stay unbound and their diagnostic points at `print`.

Mechanism: the prelude was types only, found through the global type table. A function has a body, so it lives in the `@std/core.ms+source` twin: `STANDARD_PRELUDE_FUNCTIONS` (`ms-check/src/stdlib.rs`) names it, `add_standard_prelude` binds it for non-standard modules only, and `source_standard_dependencies` adds the twin to any program with user code. Standard modules import it explicitly, since resolving the twin from inside one is a dependency cycle. A module declaring its own `print` is rejected as a duplicate name.

Apply when: adding another prelude function, or changing prelude lookup. Do not add `print` variants (`println`, `eprint`): one spelling; `stdout()`/`stderr()` cover errors, bytes and no-newline output.
Evidence: [declarations](../../documentation/core-language/modules/declarations.md), [fixture](../../tests/conformance/fixtures/snippets/authored/print-prelude.ms), `stdlib/core.ms`.
Verify: `print("hi")`, `print(42)` and `print(record)` run without an import; a module declaring `fn print` is rejected as a duplicate; `println(x)` reports the `print` hint.
