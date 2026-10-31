# conform: tags=formatter,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/result_lint_test.go:26 TestDiscardedResultLint
fn operation() Unit!: ok(unit)

fn caller() Int!:
    try operation()
    return ok(1)
