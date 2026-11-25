// conform: tags=control-flow,diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/loop_poll_test.go:41 TestLiteralCounterPollingEligibility
fn probe(flag Bool) Void {
	var i = 0
	if flag {
		while i < 1000 {
			i += 1
		}
	}
}
// expect-exit: 0
