# Changelog

## Unreleased

- Standard library: documented one failure-mode rule (absence is `Optional`, invalid external data is `Result`, violated preconditions fault) in the errors and limits contract (#168).
- Debugging: `ms debug` and `ms dap` embed Delve; VS Code no longer needs `dlv`.
- Debugging: `ms debug --break <location>` and `--script <file>`, with `--json`, run non-interactively and report Manuscript function and local names and only Manuscript frames (#352).
- Standard library: decode JSON incrementally from byte chunks with `decoder` in `@std/jsonstream.ms`, preserving values split across chunk boundaries and applying per-value limits.
- Tooling: `ms run --watch` and `ms test --watch`; versioned `--json` results for build, profile, fmt and test; `--flag=value` for value-taking options; check, lint and doc accept multiple inputs.
- CLI: `-o` directories are checked before building; `ms.lock` mismatch errors name the changed field; `ms lsp` rejects arguments.
- Builds: executables are no longer cached (every edit used to leave an unremoved 5 MB file in `.ms-cache`; delete existing ones) and `BuildChecked*` lose their cache argument; faster rebuilds through a content-addressed workspace and command replay; validated toolchain archives.
- Builds: list literals with 256 or more items compile in time proportional to their size (100,000 Int constants: about 24 s to 2 s); deeply nested List and Map literals check in near-linear time and report an uninferable element type once.
- Lint: MSL107 warns on nested `match`.
- Collections: `List.set`/`remove`/`splice`/`reverse_in_place`, `Set.add`/`remove`, `Map.remove`/`add_default`, `Bytes.reversed` and `Regex.replace_all` replace the removed copy-sounding spellings `List.with_value`/`without`/`with_values`/`reverse`, `Map.with_entry`/`without`/`with_default`/`with_default_from`, `Set.with_value`/`without`, `MapBuilder.with_entry`, `SetBuilder.with_value`, `Bytes.reverse` and `Regex.replace`; the MSL108 advisory is gone. Faults name the surviving method.
- Collections: `List.count`, `List.distinct`, in-place `List.insert` and `List.pop`.
- Standard library: `String.replace_n`, HTML parsing into `HtmlNode`, structured `Logger`/`Transport` replacing `log.write`, `http.header_values`, typed filesystem errors, full Unicode `upper`/`lower`.
- Standard library: `toml.stringify` and `yaml.stringify`; `TomlLimits` and `YamlLimits` fields default to `none`.
- Language: plain values are accepted for standard `Optional[T]` arguments; faults name operands, parameters and valid ranges.
- Packages: reusable Go packages moved under `pkg/`; update imports to `github.com/manuscript-lang/manuscript/pkg/...`.
- Maintenance: read-only verification, pinned tools, license inventories, one shared release version.
- HTTP: one ordered, ASCII case-insensitive, byte-valued `HttpHeaders` across client, server, proxy and WebSocket surfaces; common `HttpResponseMetadata`; typed `HttpMethod`, `DnsKind`, `IpAddress`, `Cidr` and `IpFamily`; `HttpClient.request`/`request_stream`; buffered `serve(max_requests:)`; empty `HttpClientOptions`/`HttpServerOptions` work. See the pull request for the migration.
