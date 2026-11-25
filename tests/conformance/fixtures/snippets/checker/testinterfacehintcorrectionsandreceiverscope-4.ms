// conform: tags=control-flow,diagnostics,formatter,interfaces,records,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/interface_hints_test.go:51 TestInterfaceHintCorrectionsAndReceiverScope
interface Named {
	fn name() String
}

type E {
	text String
}

fn E.name() String => self.text.clone()

fn named_value() Named => E("bad input")
// expect-exit: 0
