# conform: tags=mutation,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/diagnostics_test.go:66 TestCompoundAssignmentRunsNatively
export fn main() Int:
    var total = 12
    total 
