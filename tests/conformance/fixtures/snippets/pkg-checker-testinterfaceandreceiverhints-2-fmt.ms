# conform: tags=control-flow,formatter,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/interface_hints_test.go:14 TestInterfaceAndReceiverHints
impl Shape for Sq:
    def area() -> Int: self.s * self.s
