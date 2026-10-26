# conform: tags=formatter,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lint_program_test.go:89 TestSelfAssignmentDoesNotCountAsRead
def answer() -> Int:
    var _total = 0
    _total = _total + 2
    return 0
