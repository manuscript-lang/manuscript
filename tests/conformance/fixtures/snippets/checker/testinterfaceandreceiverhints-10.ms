// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/interface_hints_test.go:26 TestInterfaceAndReceiverHints
fn error_value() Error => Error.message("bad input")
// expect-error: MS2001 4:33 Error has no cases or static members, so `Error.message(...)` does not exist; if message is a module function, import it and call message(...); if it is a method, call it on a value
