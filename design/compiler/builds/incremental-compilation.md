+++
title = "Caching and Go package boundaries"
weight = 100
+++

# Caching and Go package boundaries

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Incremental work has two boundaries: compiler analysis can reuse source-derived summaries, while Go rebuilds at package granularity.

Cache parsing, checking, and module summaries by source, relevant project configuration, and dependency identity. Use canonical resolved file identity for modules; imports through different path spellings or aliases share a module summary.

Runtime, adapter schemas, and native adapters compile as separate packages. Native adapters and the application import schemas; schemas never import either. Adapter interfaces cannot use application types. Changing application code rebuilds its package; multiple generated files do not create independent compilation units. [Go build documentation](https://pkg.go.dev/cmd/go)

See [project configuration](project-configuration.md), [the pipeline](../frontend/pipeline.md), and [deterministic generation](reproducibility.md).

[Previous: Pinned dependencies and deterministic output](../builds/reproducibility.md) · [Next: Semantic conformance tests](../conformance/semantic-tests.md)
