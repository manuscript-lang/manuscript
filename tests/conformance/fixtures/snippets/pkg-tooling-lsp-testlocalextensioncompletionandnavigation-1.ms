# conform: tags=control-flow,diagnostics,faults,interfaces,modules,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/completion_test.go:17 TestLocalExtensionCompletionAndNavigation
from "./domain.ms" import Box

interface Read:
    def get() -> Int

impl Read for Box:
    def get() -> Int:
        return self.value

export def read(value: Box) -> Int:
    return value.get()
