# conform: tags=closures,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/callbacks_test.go:55 TestContextualCallbacks
let value = result(fn():
        let n = try checked()
        return ok(n)
    )
