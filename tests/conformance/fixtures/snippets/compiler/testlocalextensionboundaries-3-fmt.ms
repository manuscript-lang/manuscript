# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/local_extensions_test.go:34 TestLocalExtensionBoundaries
import invoke from "./domain.ms"

fn use(value: Box[Int]) Int:
    return invoke(value)
