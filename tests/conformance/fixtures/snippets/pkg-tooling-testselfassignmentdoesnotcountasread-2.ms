# conform: tags=diagnostics,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lint_program_test.go:94 TestSelfAssignmentDoesNotCountAsRead
def answer() -> Int:
    var total = 0
    total = total + 2
    return total
