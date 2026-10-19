# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/callbacks_test.go:90 TestCallbackInferenceRejections
let callback: fn(value: Int) Int = fn(value):
        value + 1
