# Changelog

## Unreleased

- Warn with MSL107 for nested matches and keep repository examples and implementation flat, using early-exit payload bindings, compatible `try`, or small helpers. Nested matches remain valid syntax; repository checks allow deliberate, scoped syntax and semantics regressions.

- Name operations, parameters, offending arguments and valid ranges in List/Bytes bounds, byte-value, integer-formatting radix and queue-capacity faults; preserve existing return types and bounds behavior.

- Fix standard-library data bugs: `String.upper()`/`lower()` use full Unicode case mapping (`ß` to `SS`, final sigma, `İ`); negative `split`/`replace` limits fault with the operation and parameter; `bigint.parse(max_digits: 0)` is a real zero budget; TOML and YAML parse errors report the offending line and column.
- Update the VS Code language client and packaging dependencies; the extension now requires VS Code 1.91 or newer.
- Accept `--flag=value` for value-taking CLI long options, reject empty required values and unsupported output options, and resolve project directories consistently in `ms doc`.

- Embed Delve in `ms debug` and `ms dap`; VS Code no longer needs `dlv`. CGO remains disabled; macOS still requires Apple debugserver from Xcode command line tools.

- Add `ms run --watch` and `ms test --watch` to rebuild and restart after each saved change.
- Rebuild edited programs faster: native builds share a content-addressed workspace, replay recorded compile/link commands without the go command, link a lean runtime for programs without network, system, or process imports, publish artifacts by hard link, and link Debug builds with uncompressed DWARF. `ms` loads standard declarations on first use and computes build pins while checking.
- Accept plain values for standard `Optional[T]` arguments, including `Queue[Int](capacity: 4)`, and use this convention across current call sites and examples.
- Parse HTML strings into `HtmlNode` trees with `HtmlAttribute` records, HTML5 recovery, and optional byte, depth, and node limits.
- Replace `@std/log.ms`'s `write` function with structured `Logger` and `Transport` interfaces: six levels, typed JSON fields, child bindings, record limits, and stdout/file/custom transports. Migrate calls to `create(transport: transport)` and `logger.info(message: message, fields: fields)`; fields now use `Map[String, JsonValue]`, and transports use scoped cleanup.

- Share parsing and AST graph loading across compilation and source tools; make checking, boolean optimization, and Go lowering explicit stages while preserving the checked source model.
- Group reusable Go packages under `pkg/`; Go callers must update the former root package imports to `github.com/manuscript-lang/manuscript/pkg/...`.
- Add read-only verification, pinned lint tools, environment diagnostics, and checked package/build boundaries.
- Publish documentation through GitHub Pages artifacts; generated HTML is no longer committed.
- Reuse the CLI across conformance tests, execute complete tutorial examples, and collect dependency-package coverage.
- Separate frontend facts from host runtime implementations and verify native signatures in integration tests.
- Validate compressed toolchain archives before cache publication, including interrupted downloads.
- Preserve case-equivalent HTTP header keys as separate values in insertion order, including `Set-Cookie`; reject malformed outgoing header values before emission.
- Add repeatable dependency/pin maintenance, license inventories, and one shared release version.
