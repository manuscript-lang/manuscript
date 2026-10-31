# conform: tags=formatter,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/interface_hints_test.go:13 TestInterfaceAndReceiverHints
interface Shape:
    fn area() Int

type Sq:
    s: Int
