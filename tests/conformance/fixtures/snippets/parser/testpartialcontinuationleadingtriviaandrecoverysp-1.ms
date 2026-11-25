// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/parser/partial_continuation_test.go:129 TestPartialContinuationLeadingTriviaAndRecoverySpan
// prefix
// second
fn work(a Int) Int { ... }
// expect-error: MS3000 6:1 reachable fallthrough in function returning Int; end every path with 'return <Int>' (or make the last branch return)
