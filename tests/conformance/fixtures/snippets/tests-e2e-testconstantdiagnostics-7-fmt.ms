# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/constants_test.go:18 TestConstantDiagnostics
let A = 1

def f() -> Int:
    return A()
