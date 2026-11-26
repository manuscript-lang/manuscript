// conform: tags=control-flow,diagnostics,formatter,interfaces,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/interface_hints_test.go:47 TestInterfaceHintCorrectionsAndReceiverScope
interface Shape {
	fn area() Int
}

type Sq {
	s Int
}

fn Sq.area() Int => self.s * self.s
// expect-exit: 0
