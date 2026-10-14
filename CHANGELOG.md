# Changelog

## Unreleased

- Debugging: `ms debug` and `ms dap` embed Delve; VS Code no longer needs `dlv`.
- Tooling: `ms run --watch` and `ms test --watch`; versioned `--json` results for build, profile, fmt and test; `--flag=value` for value-taking options; check, lint and doc accept multiple inputs.
- CLI: `-o` directories are checked before building; `ms.lock` mismatch errors name the changed field; `ms lsp` rejects arguments.
- Builds: faster rebuilds through a content-addressed workspace and command replay; validated toolchain archives.
- Lint: MSL107 warns on nested `match`.
- Collections: `List.set`/`remove`/`splice`/`reverse_in_place`, `Set.add`/`remove`, `Map.remove`/`add_default`, `Bytes.reversed` and `Regex.replace_all` replace the removed copy-sounding spellings `List.with_value`/`without`/`with_values`/`reverse`, `Map.with_entry`/`without`/`with_default`/`with_default_from`, `Set.with_value`/`without`, `MapBuilder.with_entry`, `SetBuilder.with_value`, `Bytes.reverse` and `Regex.replace`; the MSL108 advisory is gone. Faults name the surviving method.
- Standard library: `String.replace_n`, HTML parsing into `HtmlNode`, structured `Logger`/`Transport` replacing `log.write`, `http.header_values`, typed filesystem errors, full Unicode `upper`/`lower`.
- Standard library: `toml.stringify` and `yaml.stringify`; `TomlLimits` and `YamlLimits` fields default to `none`.
- Language: plain values are accepted for standard `Optional[T]` arguments; faults name operands, parameters and valid ranges.
- Packages: reusable Go packages moved under `pkg/`; update imports to `github.com/manuscript-lang/manuscript/pkg/...`.
- Maintenance: read-only verification, pinned tools, license inventories, one shared release version.
- HTTP: one ordered, ASCII case-insensitive, byte-valued `HttpHeaders` across client, server, proxy and WebSocket surfaces; common `HttpResponseMetadata`; typed `HttpMethod`, `DnsKind`, `IpAddress`, `Cidr` and `IpFamily`; `HttpClient.request`/`request_stream`; buffered `serve(max_requests:)`; empty `HttpClientOptions`/`HttpServerOptions` work. See the pull request for the migration.
