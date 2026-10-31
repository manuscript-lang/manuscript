# Manuscript expert wiki

Reasons and failure modes that a change should inherit. [README.md](README.md) holds the protocol: authority, entry format, how to record lessons. This page is the entry point. Each wiki page is one lesson with its own evidence links.

## Find pages

1. Match the task or touched paths to a domain below; [index.yml](index.yml) maps path globs to domains.
2. Open the domain index and read its one-line summaries; open only pages that apply.
3. Follow a page's `Topics:` footer to related pages in other domains.

## Domains

| Domain | Covers |
| --- | --- |
| [Language](language/index.md) | Syntax, types, imports, removals, language decisions |
| [Compiler and build](compiler/index.md) | Checking, lowering, MIR, Cranelift, build, fault sites |
| [Runtime](runtime/index.md) | Cancellation, cleanup, resources, networking, workers, test helpers |
| [Standard-library design](stdlib-design/index.md) | Stdlib API shape, failure modes, naming, construction |
| [Testing and conformance](testing-and-conformance/index.md) | Test layers, conformance corpus, fuzzing, fixtures |
| [Tooling and docs](tooling-and-docs/index.md) | Formatter, LSP, CLI, diagnostics, documentation, site |
| [Repository maintenance](repository/index.md) | Cleanup, CI, releases, Pages, Windows targets |
| [Benchmarks and performance](benchmarks-and-performance/index.md) | Perf and agent benchmarks, profiling |

## Topics across domains

- [Build and CI](topics/build-and-ci.md)
- [Cleanup and resources](topics/cleanup-and-resources.md)
- [Concurrency and cancellation](topics/concurrency-and-cancellation.md)
- [Diagnostics and tooling](topics/diagnostics-and-tooling.md)
- [Documentation](topics/documentation.md)
- [Errors and results](topics/errors-and-results.md)
- [Networking and HTTP](topics/networking-and-http.md)
- [Optionals](topics/optionals.md)
- [Ownership and value semantics](topics/ownership-and-values.md)
- [Performance](topics/performance.md)
- [Standard-library API shape](topics/stdlib-api-shape.md)
- [Syntax and parsing](topics/syntax-and-parsing.md)
- [Testing](topics/testing.md)
- [Types and interfaces](topics/types-and-interfaces.md)
