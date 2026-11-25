// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/result_bounds_test.go:34 TestSuccessfulResultIntBounds
alias := affine
// expect-error: MS2001 4:10 unknown binding affine; declare it with 'affine := ...' before use, define 'fn affine(...) T { ... }', or import it from a module
