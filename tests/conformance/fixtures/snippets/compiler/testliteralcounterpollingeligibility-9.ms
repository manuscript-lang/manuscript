// conform: tags=control-flow,diagnostics,mutation,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/loop_poll_test.go:50 TestLiteralCounterPollingEligibility
fn probe() Void {
	var i = 137
	while i > 0 {
		i -= 1
	}
}
// expect-exit: 0
