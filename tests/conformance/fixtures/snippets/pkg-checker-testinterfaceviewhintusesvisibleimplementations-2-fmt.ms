# conform: tags=formatter,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/interface_hints_test.go:83 TestInterfaceViewHintUsesVisibleImplementations
import Sq from "data.ms"
import Shape from "extension.ms"

fn shape() Shape: Sq(2)
