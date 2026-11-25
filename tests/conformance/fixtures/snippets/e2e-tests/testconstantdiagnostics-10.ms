// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=tests/e2e/constants_test.go:21 TestConstantDiagnostics
A := 1
A := 2
// expect-error: MS2001 5:1 duplicate or intrinsic name A; this name is already declared, imported, or built in, so rename one of them
