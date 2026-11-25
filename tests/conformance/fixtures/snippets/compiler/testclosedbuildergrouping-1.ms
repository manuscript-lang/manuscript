// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/builder_range_test.go:20 TestClosedBuilderGrouping
alias := b
// expect-error: MS2001 4:10 unknown binding b; declare it with 'b := ...' before use, define 'fn b(...) T { ... }', or import it from a module
