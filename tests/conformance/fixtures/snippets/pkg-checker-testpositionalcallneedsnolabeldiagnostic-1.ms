# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/checker/defaults_test.go:105 TestPositionalCallNeedsNoLabelDiagnostic
fn f(a: Int, b: Int) Int:
    return a + b
fn call() Int:
    return f(1, 2)
