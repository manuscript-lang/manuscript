# Wiki

Durable lessons for agents working on Manuscript. Read this page before implementation or review; update the wiki when you learn something worth remembering (protocol in [README.md](README.md)).

1. Pick domains by task and touched paths ([index.yml](index.yml) lists path globs).
2. Open the domain index, read the pages whose titles apply.
3. When a page is wrong or you learn a new lesson, fix the wiki in the same change.

| Domain | Covers |
| --- | --- |
| [Language](language/index.md) | Syntax, types, imports, removals, language decisions |
| [Compiler and build](compiler/index.md) | Checking, lowering, MIR, Cranelift, build, fault sites |
| [Runtime](runtime/index.md) | Cancellation, cleanup, resources, networking, workers, test helpers |
| [Tooling and docs](tooling-and-docs/index.md) | Formatter, LSP, CLI, diagnostics, documentation, site |
| [Repository maintenance](repository/index.md) | Cleanup, CI, releases, Pages, Windows targets |
| [Standard-library design](stdlib-design/index.md) | Stdlib API shape, failure modes, naming, construction |
| [Testing and conformance](testing-and-conformance/index.md) | Test layers, conformance corpus, fuzzing, fixtures |
| [Benchmarks and performance](benchmarks-and-performance/index.md) | Perf and agent benchmarks, profiling |
