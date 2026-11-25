// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/loop_poll_test.go:30 TestLiteralCounterPollingEligibility
fn probe(start Int, flag Bool) Void { ... }
// expect-exit: 0
