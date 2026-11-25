// conform: tags=diagnostics,parser,tier-core
// conform: phase=parse
fn f(a, b) Int => 1
// expect-error: MS1000 3:6-3:7 parameter 'a' has no type; every parameter is written name Type, e.g. a Int
// expect-format-exit: 1
