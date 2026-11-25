// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/match_bounds_test.go:57 TestBoundedMatchSelection
fn unknown(s Shape) Int => return area(s)
// expect-error: MS2001 4:14 unknown type Shape; declare it with 'type Shape:' / 'enum Shape:' / 'interface Shape:', declare it as a type parameter, or import it
// expect-error: MS2001 4:35 unknown binding area; declare it with 'area := ...' before use, define 'fn area(...) T { ... }', or import it from a module
