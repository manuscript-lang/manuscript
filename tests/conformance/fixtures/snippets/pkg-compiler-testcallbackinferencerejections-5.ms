# conform: tags=closures,control-flow,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/callbacks_test.go:88 TestCallbackInferenceRejections
let callback = fn(value: Bool):
        if value: return 1
