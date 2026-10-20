# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/callbacks_test.go:77 TestCallbackInferenceRejections
let callback: fn(value: Int) Int = fn(item: Int = 4): item
    callback()
