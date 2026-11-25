// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/interface_hints_test.go:49 TestInterfaceHintCorrectionsAndReceiverScope
fn shape() Shape => Shape(value: Sq(2))
// expect-error: MS2001 4:12 unknown type Shape; declare it with 'type Shape:' / 'enum Shape:' / 'interface Shape:', declare it as a type parameter, or import it
// expect-error: MS2001 4:21 unknown binding Shape; did you mean 'shape'?
// expect-fix: 4:21-4:26 "shape"
