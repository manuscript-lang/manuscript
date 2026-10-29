# conform: tags=diagnostics,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lint_program_test.go:89 TestSelfAssignmentDoesNotCountAsRead
fn answer() Int:
    var _total = 0
    _total = _total + 2
    return 0
