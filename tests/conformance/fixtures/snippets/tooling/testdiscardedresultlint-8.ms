# conform: tags=diagnostics,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/tooling/result_lint_test.go:22 TestDiscardedResultLint
fn consume(value: Int!) Unit: unit

fn caller() Unit:
    consume(operation())
