// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/interface_hints_test.go:62 TestInterfaceHintCorrectionsAndReceiverScope
fn f() Int => this
// expect-error: MS2001 4:15 unknown binding this; there is no 'this'; inside a method the receiver is 'self'
