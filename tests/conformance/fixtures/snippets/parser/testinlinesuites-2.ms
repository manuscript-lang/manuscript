// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/parser/parser_test.go:199 TestInlineSuites
fn f() Void => return

fn g() Void => return
// expect-exit: 0
