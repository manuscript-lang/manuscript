// conform: tags=closures,formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/lsp/callbacks_test.go:10 TestInferredCallbackParameterNavigation
fn answer() Unit:
    _values := [1, 2].map(fn value: value + 1)
