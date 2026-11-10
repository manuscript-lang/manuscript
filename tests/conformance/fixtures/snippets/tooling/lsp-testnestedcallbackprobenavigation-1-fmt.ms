// conform: tags=closures,formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/tooling/lsp/callbacks_test.go:33 TestNestedCallbackProbeNavigation
fn answer() Unit:
    offset := 7
    _values := [1].map(fn outer: [2].map(fn inner: outer + inner + offset))
