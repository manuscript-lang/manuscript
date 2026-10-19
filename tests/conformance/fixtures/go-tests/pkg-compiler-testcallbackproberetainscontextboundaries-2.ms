# conform: tags=closures,control-flow,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/callback_work_test.go:31 TestCallbackProbeRetainsContextBoundaries
let value = choose(first: fn():
        if true: return none
        return some(1)
    , second: fn(): some(2))
