# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/callbacks_test.go:107 TestInvalidCallbackInferenceDoesNotCascade
let name = apply(value: 1, transform: fn(item): missing)
    name.to_string()
