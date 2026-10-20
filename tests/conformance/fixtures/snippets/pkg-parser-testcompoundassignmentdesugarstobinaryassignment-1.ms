# conform: tags=mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/diagnostics_test.go:14 TestCompoundAssignmentDesugarsToBinaryAssignment
fn f(record: Box) Int:
    var total = 12
    total 
