# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/callbacks_test.go:75 TestCallbackInferenceRejections
let callback: fn(left: Int, right: Int) Int = fn(a, b): a - b
    callback(a: 1, b: 2)
