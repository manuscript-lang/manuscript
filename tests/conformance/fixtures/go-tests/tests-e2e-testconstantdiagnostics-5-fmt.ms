# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/constants_test.go:16 TestConstantDiagnostics
let A: Int = B + 1
let B: Int = A + 1
