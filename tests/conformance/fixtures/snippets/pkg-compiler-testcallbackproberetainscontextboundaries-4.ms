# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/callback_work_test.go:41 TestCallbackProbeRetainsContextBoundaries
let offset = 7
    let values = [1, 2].map(fn(outer): [3, 4].map(fn(inner): outer + inner + offset))
