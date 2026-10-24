# conform: tags=control-flow,diagnostics,generics,interfaces,modules,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/local_extensions_test.go:122 TestLocalExtensionUsesResolvedReceiverBounds
from "./domain.ms" import Box

interface Read:
    def get() -> Int

impl Read for Box[T]:
    def get() -> Int:
        return self.value.original()
