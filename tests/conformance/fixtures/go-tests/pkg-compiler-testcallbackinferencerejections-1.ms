# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/callbacks_test.go:73 TestCallbackInferenceRejections
let original = fn(item: Int): item
    let incompatible: fn(value: Int) Int = original
