# conform: tags=interpolation,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/diagnostics_test.go:77 TestInterpolationDiagnosticEndPosition
fn f() String: "é {1 + * 2}"
