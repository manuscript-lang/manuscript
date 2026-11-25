// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/parser/diagnostics_test.go:33 TestCompoundAssignmentRejectsReceiversThatWouldRunTwice
fn f() Void { ... }
// expect-exit: 0
