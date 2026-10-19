# conform: tags=control-flow,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/loop_poll_test.go:22 TestLiteralCounterPollingEligibility
var i = 0
    if flag:
        i = 5
