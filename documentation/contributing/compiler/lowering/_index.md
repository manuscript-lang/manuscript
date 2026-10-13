+++
title = "Go lowering"
weight = 2
+++

# Go lowering

Lowering translates checked Manuscript into Go. The generated code must preserve evaluation order, closure captures, concurrency, and block-level cleanup. These pages describe how the compiler carries those guarantees across the translation.

## Structured Go generation

`pkg/compiler/lower_*.go` consumes checked identities and the optimization view,
returning Go `ast.Expr` nodes and ordered `[]ast.Stmt` bodies. Function literals,
declarations, and the complete `ast.File` are assembled directly; lowering never
parses generated snippets. Small builders in `go_ast.go` express recurring Go
syntax without introducing another language IR. Identifiers come from checked
bindings or compiler-owned names, and source strings become quoted basic literals.
The Go printer owns operator precedence and spelling.

`print_go.go` is the source serialization boundary. It calls `format.Node` once,
then materializes source directives. Go statements have no attached-comment slot,
so lowering anchors each directive with a private label and records its source
position separately. The printer replaces each entire label line with a
column-one `//line` directive and checks that every marker was printed exactly
once. These markers use a separate counter from generated local names. Nested
closures, default arguments, actual loop labels, and generated fallback returns
retain their own locations. Runtime `SourceAt` and `TraceSource` calls remain
ordinary AST nodes with the same operand evaluation order.

This structure supports future compiler transformations; building AST nodes does
not itself make native programs faster. Checked optimization facts, typed numeric
operations, direct collection calls, and ordered source-call preparation remain
the semantic transformations. Go still performs native optimization.

The public `Result.Source` and native build/cache interfaces still accept printed
Go. `Standalone` separately parses complete generated and embedded runtime files
to combine them, and debugger path rebinding operates on final line directives.
Those existing output consumers are outside expression and statement lowering.

The compiler's `testdata/go-ast` fixture retains source and generated Go from
commit `4d9bce1f`, before AST lowering. Its differential test compares parsed
executable structure and source directives, then builds and executes both forms.
Do not refresh this independent baseline just because output formatting changes.

- [Function and concurrency API lowering](function-and-task-calls.md)
- [Source guarantees and Go representations](value-representations.md)
- [Evaluation order and call preparation](evaluation-order.md)
- [Cleanup and fault lowering](cleanup-and-faults.md)
