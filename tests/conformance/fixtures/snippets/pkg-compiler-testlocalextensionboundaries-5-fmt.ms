# conform: tags=control-flow,formatter,generics,interfaces,modules,parser,stdlib-cleanup,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/compiler/local_extensions_test.go:46 TestLocalExtensionBoundaries
from "@std/core.ms" import Closeable

impl Closeable for Box[T]:
    def close() -> Unit:
        return

export def loaded() -> Int:
    return 1
