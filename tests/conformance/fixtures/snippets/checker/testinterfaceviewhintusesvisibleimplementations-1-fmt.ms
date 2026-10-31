# conform: tags=control-flow,formatter,interfaces,modules,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/interface_hints_test.go:79 TestInterfaceViewHintUsesVisibleImplementations
import Sq from "data.ms"

export interface Shape:
    fn area() Int

impl Shape for Sq:
    fn area() Int: self.s * self.s
