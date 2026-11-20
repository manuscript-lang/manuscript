[Wiki](../index.md) › [Tooling and docs](index.md)

# Tools in Manuscript read libms through flat tables

Decision (C rewrite, 2026-11-20): lint, docs and symbol search are Manuscript programs over `libms`, and the Rust `ms` is the byte-for-byte oracle until the Rust is deleted. A Manuscript program holds no C pointer, so each `libms` entry point in `compiler/include/ms/tool.h` returns a `List[Int]` of fixed-width records (plus `List[String]` where text is needed). The record layout is written twice, in `tool.h` and `tools/ms/syntax.ms`, and the two are one contract.

Verified: a tool links `libmstool.a` (`make target/c-tool/libmstool.a`; `tool.c` includes `libms.c`, so it carries the whole library and needs the runtime's `ms_list_push`) and runs with `ms run tool.ms --link libmstool.a`. The project root is the entry file's directory, so tools sit under `tools/ms/` with its own `ms.toml`.

Apply when: moving a Rust tool rule or report into Manuscript, or adding a table to `tool.h`.
Evidence: [tool.h](../../compiler/include/ms/tool.h), [syntax.ms](../../tools/ms/syntax.ms), [lexical lint](../../tools/ms/lint/text.ms), [differential harness](../../tools/ms/lint_diff.ms).
Verify: `make c-tools-test` lints seeded mutations of corpus files with both linters and requires equal findings.

Verified: copy `String.view_bytes()` of a short view with `as_bytes()` until [#4655](https://github.com/manuscript-lang/manuscript/issues/4655) is fixed; the borrowed bytes change after another view is taken.
