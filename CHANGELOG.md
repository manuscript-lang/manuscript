# Changelog

## Unreleased

- Check the `-o` directory before building; name the changed field in `ms.lock` mismatch errors and drop Go internals from lock parse errors; reject arguments to `ms lsp`; fuzz `FuzzFormat` in `make fuzz`.
- Fix Map and Set lookups after removing the last remaining key: a stale key index made later distinct keys share one entry (#316).
- Add receiver-returning `Map.remove` and `List.splice` aliases, preserving legacy lookup, insertion order, strict splice bounds and faults; extend native dispatch, mutation analysis and preferred-name advisories.
- Add `String.replace_n` with a required finite replacement cap and the existing literal/scalar, zero/negative and fault behavior; current `replace`/`replace_first` signatures remain compatible.
- Warn with MSL107 for nested matches and keep repository examples and implementation flat, using early-exit payload bindings, compatible `try`, or small helpers. Nested matches remain valid syntax; repository checks allow deliberate, scoped syntax and semantics regressions.
- List loops and callbacks follow Go slice range behavior without traversal copies: capture backing and initial length once, observe in-place writes, and do not extend traversal on append. Shrinking shifts/reslices without clearing valid tail values; removed references can remain in spare capacity. Explicit clones/slices and Map/Set membership snapshots retain their contracts.
- Add MSL108 advisories for equivalent preferred collection mutation, byte-copy reversal and regex replacement names, including stored methods; preserve user methods, callable fields and existing execution.
- Add preferred `List.set`/`remove`/`reverse_in_place`, copying `List.reversed`/`Bytes.reversed`, `Set.add`/`remove`, `String.replace_first`, and `Regex.replace_all` spellings. Existing names remain compatible, including receiver returns, replacement caps, limits, and errors.
- Report duration-unit property faults at the member token after evaluating the receiver, preserving source order and numeric widths.
- Reduce Debug native compilation work for large flat primitive literals while retaining fresh list storage; Release lowering is unchanged. Add `CompileSourceForBuild` and `CompileFileForBuild` to select lowering before Go generation. Existing `compiler.Result` layout, source overrides and legacy compile/build calls remain supported. Repeated Debug construction and fixed rooted literal data remain sensitive to GC settings.

- Name operations, parameters, offending arguments and valid ranges in List/Bytes bounds, byte-value, integer-formatting radix and queue-capacity faults; preserve existing return types and bounds behavior.
- Identify Decimal arithmetic overflow by operator, operands and the finite magnitude limit, without changing arithmetic or rounding.
- Add versioned `fmt --check --json` and `test --json` results, preserving test streams and partial outcomes; display explicit and discovered fmt paths consistently.
- Accept independent input collections and standalone directories in check, lint, and doc; aggregate deterministic reports without combining applications or changing fmt discovery.
- Add versioned build/profile JSON results with partial artifact inventories; add profile `--out-dir` and `ms version` aliases while retaining existing spellings.

- Fix standard-library data bugs: `String.upper()`/`lower()` use full Unicode case mapping (`ß` to `SS`, final sigma, `İ`); negative `split`/`replace` limits fault with the operation and parameter; `bigint.parse(max_digits: 0)` is a real zero budget; TOML and YAML parse errors report the offending line and column.
- Update the VS Code language client and packaging dependencies; the extension now requires VS Code 1.91 or newer.
- Accept `--flag=value` for value-taking CLI long options, reject empty required values and unsupported output options, and resolve project directories consistently in `ms doc`.

- Embed Delve in `ms debug` and `ms dap`; VS Code no longer needs `dlv`. CGO remains disabled; macOS still requires Apple debugserver from Xcode command line tools.

- Add `ms run --watch` and `ms test --watch` to rebuild and restart after each saved change.
- Rebuild edited programs faster: native builds share a content-addressed workspace, replay recorded compile/link commands without the go command, link a lean runtime for programs without network, system, or process imports, publish artifacts by hard link, and link Debug builds with uncompressed DWARF. `ms` loads standard declarations on first use and computes build pins while checking.
- Accept plain values for standard `Optional[T]` arguments, including `Queue[Int](capacity: 4)`, and use this convention across current call sites and examples.
- Name Int division/remainder, Decimal division, and Duration/Instant arithmetic faults with the offending operands and valid constraints, retaining existing numeric outcomes and cancellation.
- Parse HTML strings into `HtmlNode` trees with `HtmlAttribute` records, HTML5 recovery, and optional byte, depth, and node limits.
- Replace `@std/log.ms`'s `write` function with structured `Logger` and `Transport` interfaces: six levels, typed JSON fields, child bindings, record limits, and stdout/file/custom transports. Migrate calls to `create(transport: transport)` and `logger.info(message: message, fields: fields)`; fields now use `Map[String, JsonValue]`, and transports use scoped cleanup.
- Report invalid Scheduler limits/drain, TaskGroup timeout and sleep duration with the operation, parameter, original value and valid range, preserving all scheduling and cancellation contracts.

- Share parsing and AST graph loading across compilation and source tools; make checking, boolean optimization, and Go lowering explicit stages while preserving the checked source model.
- Group reusable Go packages under `pkg/`; Go callers must update the former root package imports to `github.com/manuscript-lang/manuscript/pkg/...`.
- Add read-only verification, pinned lint tools, environment diagnostics, and checked package/build boundaries.
- Publish documentation through GitHub Pages artifacts; generated HTML is no longer committed.
- Reuse the CLI across conformance tests, execute complete tutorial examples, and collect dependency-package coverage.
- Separate frontend facts from host runtime implementations and verify native signatures in integration tests.
- Validate compressed toolchain archives before cache publication, including interrupted downloads.
- Preserve case-equivalent HTTP header keys as separate values in insertion order, including `Set-Cookie`; reject malformed outgoing header values before emission.
- Add `http.header_values` for ASCII case-insensitive, value-preserving lookup across list-valued HTTP header maps, with separate returned list membership.
- Return typed filesystem errors for non-empty directories, wrong entry kinds, negative absolute seeks and handle-mode misuse. Validate HTTP paths before normalization, reject encoded slash/NUL, normalize dot segments, and return `HttpError.InvalidInput` for malformed ports in all HTTP clients.
- Add repeatable dependency/pin maintenance, license inventories, and one shared release version.
