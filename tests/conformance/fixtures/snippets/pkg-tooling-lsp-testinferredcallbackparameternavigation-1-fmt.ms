# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/callbacks_test.go:10 TestInferredCallbackParameterNavigation
def answer() -> Unit:
    let values = [1, 2].map(lambda value: value + 1)
