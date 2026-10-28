# conform: tags=control-flow,diagnostics,generics,interfaces,modules,stdlib-cleanup,tier-stdlib
# conform: phase=check
# conform: origin=pkg/compiler/local_extensions_test.go:46 TestLocalExtensionBoundaries
import Closeable from "@std/core.ms"

impl Closeable for Box[T]:
    fn close() Unit:
        return

export fn loaded() Int:
    return 1
