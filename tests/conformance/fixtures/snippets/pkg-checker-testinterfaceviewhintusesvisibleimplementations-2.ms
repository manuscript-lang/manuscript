# conform: tags=diagnostics,modules,tier-core
# conform: phase=check
# conform: origin=pkg/checker/interface_hints_test.go:83 TestInterfaceViewHintUsesVisibleImplementations
import Sq from "data.ms"
import Shape from "extension.ms"

fn shape() Shape: Sq(2)
