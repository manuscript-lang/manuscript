# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/analysis_test.go:17 TestOverlayImportsAndNavigation
from "./dep.ms" import answer

def value() -> Int:
    return answer()
