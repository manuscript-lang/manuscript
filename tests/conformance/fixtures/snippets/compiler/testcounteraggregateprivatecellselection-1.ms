// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/counter_aggregate_test.go:75 TestCounterAggregatePrivateCellSelection
alias := cell
// expect-error: MS2001 4:10 unknown binding cell; declare it with 'cell := ...' before use, define 'fn cell(...) T { ... }', or import it from a module
