# conform: tags=control-flow,diagnostics,interfaces,tier-core
# conform: phase=check
# conform: origin=pkg/checker/interface_hints_test.go:14 TestInterfaceAndReceiverHints
impl Shape for Sq:
    def area() -> Int: self.s * self.s
