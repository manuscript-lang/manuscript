# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/callbacks_test.go:103 TestInvalidCallbackInferenceDoesNotCascade
let names = [1, 2].map(fn(item): missing)
    names.join(",")
