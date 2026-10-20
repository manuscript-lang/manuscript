# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/analysis_test.go:17 TestOverlayImportsAndNavigation
import answer from "./dep.ms"
fn value() Int:
    return answer()
