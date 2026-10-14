# Changelog

## Unreleased

- Debugging: `ms debug` and `ms dap` embed Delve; VS Code no longer needs `dlv`.
- Tooling: `ms run --watch` and `ms test --watch`; versioned `--json` results for build, profile, fmt and test; `--flag=value` for value-taking options; check, lint and doc accept multiple inputs.
- CLI: `-o` directories are checked before building; `ms.lock` mismatch errors name the changed field; `ms lsp` rejects arguments.
- Builds: executables are no longer cached (every edit used to leave an unremoved 5 MB file in `.ms-cache`; delete existing ones) and `BuildChecked*` lose their cache argument; faster rebuilds through a content-addressed workspace and command replay; validated toolchain archives.
- Lint: MSL107 warns on nested `match`; MSL108 suggests the preferred collection, byte and regex method names.
- Collections: preferred mutation names (`List.set`/`remove`/`splice`/`reverse_in_place`, `Set.add`/`remove`, `Map.remove`, `Regex.replace_all`) alongside the legacy spellings; Map and Set lookups fixed after removing the last key (#316).
- Standard library: `String.replace_n`, HTML parsing into `HtmlNode`, structured `Logger`/`Transport` replacing `log.write`, `http.header_values`, typed filesystem errors, full Unicode `upper`/`lower`.
- Language: plain values are accepted for standard `Optional[T]` arguments; faults name operands, parameters and valid ranges.
- Packages: reusable Go packages moved under `pkg/`; update imports to `github.com/manuscript-lang/manuscript/pkg/...`.
- Maintenance: read-only verification, pinned tools, license inventories, one shared release version.
