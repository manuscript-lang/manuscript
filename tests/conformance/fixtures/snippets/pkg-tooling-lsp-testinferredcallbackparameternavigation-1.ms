# conform: tags=closures,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/callbacks_test.go:10 TestInferredCallbackParameterNavigation
def answer() -> Unit:
    let _values = [1, 2].map(lambda value: value + 1)
