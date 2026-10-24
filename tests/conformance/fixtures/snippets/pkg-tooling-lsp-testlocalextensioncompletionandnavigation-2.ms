# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/completion_test.go:26 TestLocalExtensionCompletionAndNavigation
from "./domain.ms" import Box
from "./extension.ms" import read

def use(value: Box) -> Int:
    return value.value
