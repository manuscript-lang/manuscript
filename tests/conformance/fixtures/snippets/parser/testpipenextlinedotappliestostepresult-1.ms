// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/parser/pipe_test.go:98 TestPipeNextLineDotAppliesToStepResult
fn f() Int {
	v := x
}
// expect-error: MS2001 5:10 unknown binding x; declare it with 'x := ...' before use, define 'fn x(...) T { ... }', or import it from a module
// expect-error: MS3000 4:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
