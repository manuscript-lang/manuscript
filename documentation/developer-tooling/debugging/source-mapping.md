+++
title = "Generated Go source mapping"
weight = 119
+++

# Generated Go source mapping

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Generated Go includes line directives that point back to Manuscript statements. A debug build keeps symbols and disables optimization and inlining so the debugger has enough information to follow the source.

[Go line directives](https://pkg.go.dev/cmd/compile#hdr-Line_Directives)

## Source positions and build mode

Line directives provide native source position mapping. Retaining symbols and disabling optimization and inlining in a debug build preserve information needed by the debugger, while build metadata supplies the type and local-variable descriptions.

Mapping a source line does not by itself explain a generated cleanup frame or a source alternative value. See [the Manuscript debugger layer](debugger-integration.md).

[Previous: Build, source, and task metadata](metadata.md) · [Next: Debugger transport and source interpretation](debugger-integration.md)
