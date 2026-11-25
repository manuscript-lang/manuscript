// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/counter_aggregate_test.go:77 TestCounterAggregatePrivateCellSelection
fn probe() Int {
	cell := Cell(0)
}
// expect-error: MS2001 5:13 unknown binding Cell; declare it with 'Cell := ...' before use, define 'fn Cell(...) T { ... }', or import it from a module
// expect-error: MS3000 4:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
