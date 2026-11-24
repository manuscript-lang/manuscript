// conform: tags=closures,diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/lsp/callbacks_test.go:33 TestNestedCallbackProbeNavigation
fn answer() Void:
    offset := 7
    _values := [1].map(outer => [2].map(inner => outer + inner + offset))
