# conform: tags=closures,mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/callback_work_test.go:60 TestCallbackProbeRetainsDiagnostics
var value = 1
    let values = [1].map(fn(item):
        value = 2
        return item
    )
