# conform: tags=control-flow,formatter,generics,interfaces,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/local_extensions_test.go:122 TestLocalExtensionUsesResolvedReceiverBounds
from "./domain.ms" import Box

interface Read:
    def get() -> Int

impl Read for Box[T]:
    def get() -> Int:
        return self.value.original()
