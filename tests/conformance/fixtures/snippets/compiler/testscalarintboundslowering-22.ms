// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/int_bounds_test.go:38 TestScalarIntBoundsLowering
fn probe(start Int, flag Bool) Int { ... }
// expect-error: MS3000 4:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
