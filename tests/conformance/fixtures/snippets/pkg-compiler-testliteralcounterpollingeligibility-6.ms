# conform: tags=control-flow,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/loop_poll_test.go:25 TestLiteralCounterPollingEligibility
var i = 0
    while i < 3:
        i += 1
