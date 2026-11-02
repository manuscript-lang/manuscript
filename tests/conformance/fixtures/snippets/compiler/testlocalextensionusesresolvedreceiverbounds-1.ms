# conform: tags=control-flow,diagnostics,generics,interfaces,modules,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/local_extensions_test.go:122 TestLocalExtensionUsesResolvedReceiverBounds
import Box from "./domain.ms"

interface Read:
    fn get() Int

impl Read for Box[T]:
    fn get() Int:
        return self.value.original()
