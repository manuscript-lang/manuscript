# Manuscript tooling

See [commands and limits](../../documentation/developer-tooling/implementation.md) for formatting, lint, LSP, debugging, profiling, and source inspection. The [architecture guide](../../documentation/contributing/architecture.md) maps the implementation.

API documentation JSON uses format 2. Declarations retain `fields` for stored
fields and `operations` for callable methods, and expose live read-only members
in `accessors` as `name: ValueType`. Their `members` entries have kind `accessor`
and source signatures such as `get length -> Int`. Accessors are never exported
as mutable fields or function-valued implementation signatures.

Inspection JSON uses format 2. Accessor entities have kind `accessor` and their
value type. Each evaluated member read contributes an execution site of kind
`accessor` to `calls`, retaining the selected target and caller's source span.
Stored-field reads and bound method references do not create such sites. This
also lets static diagrams include execution through an accessor without changing
its source expression into a call. Inspection and debugger value rendering do
not evaluate accessors.
