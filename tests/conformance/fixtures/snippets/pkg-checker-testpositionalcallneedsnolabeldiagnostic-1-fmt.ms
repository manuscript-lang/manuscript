# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/defaults_test.go:105 TestPositionalCallNeedsNoLabelDiagnostic
def f(a: Int, b: Int) -> Int:
    return a + b

def call() -> Int:
    return f(1, 2)
