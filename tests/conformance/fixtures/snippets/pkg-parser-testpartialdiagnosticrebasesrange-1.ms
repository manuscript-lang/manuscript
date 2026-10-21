# conform: tags=control-flow,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/diagnostics_test.go:64 TestPartialDiagnosticRebasesRange
fn before() Int: 1
fn broken(a: Bool, b: Bool) Int:
    if a && b:
        return 1
    return 2
fn after() Int: 3
