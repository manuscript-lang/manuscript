# conform: tags=control-flow,diagnostics,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lint_program_test.go:96 TestSelfAssignmentDoesNotCountAsRead
def answer() -> Int:
    var total = 0
    total = total + 2
    if total > 1:
        return 1

    return 0
