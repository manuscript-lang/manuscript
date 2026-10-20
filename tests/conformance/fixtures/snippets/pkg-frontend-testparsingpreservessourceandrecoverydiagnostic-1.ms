# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/frontend/source_test.go:12 TestParsingPreservesSourceAndRecoveryDiagnostics
fn value() Int:
    return 3
fn broken(
