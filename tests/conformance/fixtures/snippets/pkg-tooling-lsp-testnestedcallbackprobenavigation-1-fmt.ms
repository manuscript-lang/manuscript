# conform: tags=closures,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/callbacks_test.go:33 TestNestedCallbackProbeNavigation
def answer() -> Unit:
    let offset = 7
    let _values = [1].map(lambda outer: [2].map(lambda inner: outer + inner + offset))
