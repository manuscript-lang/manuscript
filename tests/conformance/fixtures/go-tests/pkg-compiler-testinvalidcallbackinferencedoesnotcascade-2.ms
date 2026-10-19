# conform: tags=closures,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/callbacks_test.go:105 TestInvalidCallbackInferenceDoesNotCascade
let names = [1].map(fn(item): missing)
    let next = names.map[String]
