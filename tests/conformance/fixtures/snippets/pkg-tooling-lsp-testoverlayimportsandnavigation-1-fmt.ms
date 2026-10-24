# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/analysis_test.go:17 TestOverlayImportsAndNavigation
from "./dep.ms" import answer

def value() -> Int:
    return answer()
