# conform: tags=control-flow,diagnostics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/checker/interface_hints_test.go:47 TestInterfaceHintCorrectionsAndReceiverScope
interface Shape:
    fn area() Int
type Sq:
    s: Int
impl Shape for Sq:
    fn area() Int: self.s * self.s
