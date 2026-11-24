// conform: tags=closures,formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/lsp/callbacks_test.go:10 TestInferredCallbackParameterNavigation
fn answer() Void:
    _values := [1, 2].map(value => value + 1)
