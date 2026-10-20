# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/diagnostics_test.go:39 TestCompoundAssignmentRejectsReceiversThatWouldRunTwice
fn f() Unit:
    total + = 1
