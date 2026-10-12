+++
title = "Application hosts"
weight = 44
+++

# Application hosts

[Guide index](../_index.md) · [Design index](../../_index.md)

A host starts application code and sets its execution lifetime, cancellation, and limits. The CLI host invokes `main` once; an HTTP host gives each request its own execution context.

- [HTTP request hosts](http.md) — Use HTTP clients or request hosts with bounded bodies and cleanup.
- [CLI application hosts](cli.md)
