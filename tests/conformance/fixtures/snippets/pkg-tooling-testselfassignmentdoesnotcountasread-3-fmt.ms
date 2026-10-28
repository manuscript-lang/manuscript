# conform: tags=formatter,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lint_program_test.go:95 TestSelfAssignmentDoesNotCountAsRead
fn answer() Int:
    var total = 0
    var other = 0
    other = total + 1
    total = total + 2
    return other
