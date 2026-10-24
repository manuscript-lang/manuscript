# conform: tags=control-flow,diagnostics,interfaces,modules,tier-core
# conform: phase=check
# conform: origin=pkg/checker/interface_hints_test.go:79 TestInterfaceViewHintUsesVisibleImplementations
from "data.ms" import Sq

export interface Shape:
    def area() -> Int

impl Shape for Sq:
    def area() -> Int: self.s * self.s
