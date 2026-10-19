# conform: tags=closures,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/callback_work_test.go:35 TestCallbackProbeRetainsContextBoundaries
let value = choose(first: fn():
        let value = try checked()
        return Result[Int, TextError].ok(value)
    , second: fn(): ok(4))
