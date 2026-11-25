// conform: tags=diagnostics,interfaces,records,tier-core
// conform: phase=check
// conform: origin=tests/e2e/inherent_methods_test.go:38 TestInherentImplRejections
type B {
	x Int
}

fn B.m() Int { ... }
// expect-error: MS3000 8:6 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
