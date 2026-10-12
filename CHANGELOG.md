# Changelog

## Unreleased

- Parse HTML strings into `HtmlNode` trees with `HtmlAttribute` records, HTML5 recovery, and optional byte, depth, and node limits.
- Replace `@std/log.ms`'s `write` function with structured `Logger` and `Transport` interfaces: six levels, typed JSON fields, child bindings, record limits, and stdout/file/custom transports. Migrate calls to `create(transport: transport)` and `logger.info(message: message, fields: some(value: fields))`; fields now use `Map[String, JsonValue]`, and transports use scoped cleanup.

- Share parsing and AST graph loading across compilation and source tools; make checking, boolean optimization, and Go lowering explicit stages while preserving the checked source model.
- Group reusable Go packages under `pkg/`; Go callers must update the former root package imports to `github.com/manuscript-lang/manuscript/pkg/...`.
- Add read-only verification, pinned lint tools, environment diagnostics, and checked package/build boundaries.
- Publish documentation through GitHub Pages artifacts; generated HTML is no longer committed.
- Reuse the CLI across conformance tests, execute complete tutorial examples, and collect dependency-package coverage.
- Separate frontend facts from host runtime implementations and verify native signatures in integration tests.
- Validate compressed toolchain archives before cache publication, including interrupted downloads.
- Add repeatable dependency/pin maintenance, license inventories, and one shared release version.
