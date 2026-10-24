# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/constants_test.go:12 TestConstantDiagnostics
def f() -> Int:
    return 1

let X = f()
