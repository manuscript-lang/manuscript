// conform: tags=formatter,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/terse_data_test.go:11 TestTerseDataRejections
fn f(first Int, second Int) Int => return first + second
// expect-format: rewritten
// expect-formatted: fn f(first, second Int) Int => return first + second
