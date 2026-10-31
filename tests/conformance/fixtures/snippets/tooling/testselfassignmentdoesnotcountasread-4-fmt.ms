# conform: tags=control-flow,formatter,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lint_program_test.go:96 TestSelfAssignmentDoesNotCountAsRead
fn answer() Int:
    var total = 0
    total = total + 2
    if total > 1:
        return 1

    return 0
