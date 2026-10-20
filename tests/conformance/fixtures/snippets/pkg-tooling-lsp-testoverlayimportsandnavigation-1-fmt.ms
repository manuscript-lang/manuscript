# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/analysis_test.go:17 TestOverlayImportsAndNavigation
import answer from "./dep.ms"
fn value() Int:
    return answer()
