[Wiki](../index.md) › [Compiler](index.md) › Fallible native calls share one error builder

# Fallible native calls share one error builder

The `Error` for a nonzero native status (kind, `domain: words`, optional native text) used to be a chain of up to 16 cases inlined at every call site. In the web server that was 284 error constructions and more than half of its MIR; `WebSocketSink.write` compiled to 85 KB from three lines. `Cx::status_error_fn` now makes one `status_error` function per (error type, status table, domain, has text) and a site calls it with the status and the taken `err` text.

- Server binary 3.96 to 3.65 MB, MIR 12,070 to 6,414 lines, conformance unchanged.
- The same shape is worth looking for elsewhere: code that expands per call site and does not depend on the site (see `ms build --emit mir` and `nm --size-sort`).
