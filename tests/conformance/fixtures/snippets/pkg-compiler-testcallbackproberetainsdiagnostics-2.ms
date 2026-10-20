# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/callback_work_test.go:65 TestCallbackProbeRetainsDiagnostics
let callback: fn(value: Int) Int = apply(value: 1, transform: fn(base): fn(item: Int = 4): item + base)
    callback()
