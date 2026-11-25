// conform: tags=control-flow,diagnostics,formatter,interfaces,records,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/interface_hints_test.go:24 TestInterfaceAndReceiverHints
interface Named {
	fn name() String
}

type E {
	text String
}

fn E.name() String => this.text
// expect-error: MS2001 12:23 unknown binding this; the receiver in a method is 'self'; write self instead of this
// expect-fix: 12:23-12:27 "self"
