[Wiki](../index.md) › [Language](index.md)

# `print` is the one prelude function

Decision: Chinmay asked for a `print` function (2026-11-03) after a Ruby comparison found hello world needed `stdout().write(...)?`. `print(value)` is in the prelude: any value as text (the `to_string()` representation) plus a newline, never fails, buffered like `stdout()`. It is a deliberate exception to [methods before free functions](methods-before-free-functions.md): there is no receiver. `println`, `printf`, `puts` and `echo` stay unbound and their diagnostic points at `print`.

Mechanism: the prelude was types only, found through the global type table. A function has a body, so it lives in the `@std/core.ms+source` twin: the standard-library loader in `src/compiler/check` (`std_cache.c`, `lazy_std.c`) binds it for non-standard modules only and adds the twin to any program with user code. Standard modules import it explicitly, since resolving the twin from inside one is a dependency cycle. A module declaring its own `print` is rejected as a duplicate name.

Apply when: adding another prelude function, or changing prelude lookup. Do not add `print` variants (`println`, `eprint`): one spelling; `stdout()`/`stderr()` cover errors, bytes and no-newline output.
Evidence: [declarations](../../../documentation/core-language/modules/declarations.md), [fixture](../../../tests/lang/strings/print-prelude.ms), `src/stdlib/core/core.ms`.
Verify: `print("hi")`, `print(42)` and `print(record)` run without an import; a module declaring `fn print` is rejected as a duplicate; `println(x)` reports the `print` hint.
