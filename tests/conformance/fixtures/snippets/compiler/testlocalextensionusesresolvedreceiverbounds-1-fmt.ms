# conform: tags=control-flow,formatter,generics,interfaces,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/local_extensions_test.go:122 TestLocalExtensionUsesResolvedReceiverBounds
import Box from "./domain.ms"

interface Read:
    fn get() Int

impl Read for Box[T]:
    fn get() Int:
        return self.value.original()
