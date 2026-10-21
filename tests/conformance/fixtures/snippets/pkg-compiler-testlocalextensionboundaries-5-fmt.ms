# conform: tags=control-flow,formatter,generics,interfaces,modules,parser,stdlib-cleanup,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/compiler/local_extensions_test.go:46 TestLocalExtensionBoundaries
import Closeable from "@std/core.ms"
impl Closeable for Box[T]:
    fn close() Unit:
        return
export fn loaded() Int:
    return 1
