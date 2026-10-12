+++
title = "Caching and Go package boundaries"
weight = 100
+++

# Caching and Go package boundaries

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Caching can save the compiler from repeating parsing and checking. It cannot always save Go from rebuilding an application package. This page separates those two boundaries and explains what must be included in a cache key.

Cache parsing, checking, and module summaries by source, relevant project configuration, and dependency identity. Use canonical resolved file identity for modules; imports through different path spellings or aliases share a module summary.

Runtime, adapter schemas, and native adapters compile as separate packages. Native adapters and the application import schemas; schemas never import either. Adapter interfaces cannot use application types. Changing application code rebuilds its package; multiple generated files do not create independent compilation units. [Go build documentation](https://pkg.go.dev/cmd/go)

See [project configuration](project-configuration.md), [the pipeline](../frontend/pipeline.md), and [deterministic generation](reproducibility.md).

[Previous: Pinned dependencies and deterministic output](../builds/reproducibility.md) · [Next: Semantic conformance tests](../conformance/semantic-tests.md)
