// conform: tags=control-flow,diagnostics,interfaces,records,strings,tier-core
// conform: phase=check
// conform: origin=pkg/checker/interface_hints_test.go:24 TestInterfaceAndReceiverHints
interface Named:
    fn name() String

type E:
    text: String

fn E.name() String: this.text
