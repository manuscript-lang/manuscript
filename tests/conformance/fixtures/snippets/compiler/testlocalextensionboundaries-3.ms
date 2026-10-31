# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/local_extensions_test.go:34 TestLocalExtensionBoundaries
import invoke from "./domain.ms"

fn use(value: Box[Int]) Int:
    return invoke(value)
