[Wiki](../index.md) › [Tooling and docs](index.md)

# Tools in Manuscript read libms through flat tables

Decision (C rewrite, 2026-11-20): lint, docs and symbol search are Manuscript programs over `libms`, and the Rust `ms` is the byte-for-byte oracle until the Rust is deleted. A Manuscript program holds no C pointer, so each `libms` entry point in `compiler/include/ms/tool.h` returns a `List[Int]` of fixed-width records (plus `List[String]` where text is needed). The record layout is written twice, in `tool.h` and `tools/ms/syntax.ms`, and the two are one contract.

Verified: a tool links `libmstool.a` (`make target/c-tool/libmstool.a`; `tool.c` includes `libms.c`, so it carries the whole library and needs the runtime's `ms_list_push`) and runs with `ms run tool.ms --link libmstool.a`. The project root is the entry file's directory, so tools sit under `tools/ms/` with its own `ms.toml`.

Verified: `ms_tool_parse` returns an opaque `Tree` held by C; `tools/ms/syntax.ms` decodes its preorder records into parallel columns (`kind`, `first`, `next`, ...), and `tools/ms/dump.ms` prints the canonical dump from them. The text equals `ms_syntax_dump ast` on every `.ms` file in the repository, which is the proof that the table loses nothing.

Apply when: moving a Rust tool rule or report into Manuscript, or adding a table to `tool.h`.
Evidence: [tool.h](../../compiler/include/ms/tool.h), [syntax.ms](../../tools/ms/syntax.ms), [dump](../../tools/ms/dump.ms), [lexical lint](../../tools/ms/lint/text.ms), [differential harness](../../tools/ms/lint_diff.ms).
Verify: `make c-tools-test` compares the dumps over the whole corpus and lints seeded mutations of corpus files with both linters, requiring equal findings.

Verified: copy `String.view_bytes()` of a short view with `as_bytes()` until [#4655](https://github.com/manuscript-lang/manuscript/issues/4655) is fixed; the borrowed bytes change after another view is taken.

Verified: the docs generator (`tools/ms/docgen.ms`) and description inventory (`doc_inventory.ms`) are pure rendering over an API model and reproduce all 103 `ms-docgen` files, `stdlib.json` and the coverage JSON byte for byte. The model comes from the temporary Rust example `crates/ms-tooling/examples/api_model.rs` until the C checker's declaration columns can feed a Manuscript model builder; the example is deleted with the Rust docs generator.

Search: [search.ms](../../tools/ms/search.ms) ports `ms search_symbol` (pages, fuzzy ranking, `name_rank`, text and JSON output) over the dumped API model and matches the Rust command on every query of `tools/ms/search_queries.txt` in text, `--json` and `--limit 10`. It has library symbols only until the C checker supplies project symbols.

Views: [views.ms](../../tools/ms/views.ms) ports the ten `ms diagram` views (tree, ASCII, Mermaid and JSON renderings) over the fact model that `ms-tooling-dev facts FILE` dumps, and `tools/ms/views-diff.sh` requires equal output with the Rust views (`ms-tooling-dev view`) for every view, format, entity and depth on three fixtures. Fact collection (`collect_facts`, `inspect::collect`) and the API model (`guide/api.rs`) stay in Rust: they read the Rust checker's program, so they move only when the C checker's columns can feed a Manuscript builder. Ownership rule met while porting: a builder record must not hold the model (storing `self` moves it); pass the model to each method instead.
