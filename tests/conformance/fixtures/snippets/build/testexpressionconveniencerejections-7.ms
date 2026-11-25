// conform: tags=diagnostics,strings,tier-core
// conform: phase=check
// conform: origin=pkg/build/expression_conveniences_test.go:18 TestExpressionConvenienceRejections
fn f() String => return "a" + 1
// expect-error: MS3001 4:29 operator operands require the same independently known type, found String + Int; convert one side so both have one type (e.g. interpolate into text with f"{value}", or convert between Int and Float)
