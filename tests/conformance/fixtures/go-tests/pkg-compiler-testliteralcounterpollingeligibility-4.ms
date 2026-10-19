# conform: tags=match,mutation,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/loop_poll_test.go:23 TestLiteralCounterPollingEligibility
var i = 0
    let captured = match some(0):
        some(n):
            i = start
            n
        none: 0
