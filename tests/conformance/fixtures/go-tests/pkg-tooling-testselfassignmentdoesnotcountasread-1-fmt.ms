# conform: tags=formatter,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lint_program_test.go:89 TestSelfAssignmentDoesNotCountAsRead
fn answer() Int:
    var total = 0
    total = total + 2
    return 0
