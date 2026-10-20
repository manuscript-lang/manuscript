# conform: tags=closures,control-flow,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/callback_work_test.go:27 TestCallbackProbeRetainsContextBoundaries
let value = result(fn():
        if true: return error(TextError("failed"))
        return ok(4)
    )
