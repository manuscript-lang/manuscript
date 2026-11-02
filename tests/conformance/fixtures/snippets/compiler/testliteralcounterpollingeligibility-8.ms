# conform: tags=control-flow,diagnostics,mutation,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/loop_poll_test.go:41 TestLiteralCounterPollingEligibility
fn probe(flag: Bool) Unit:
    var i = 0
    if flag:
        while i < 1000:
            i += 1
