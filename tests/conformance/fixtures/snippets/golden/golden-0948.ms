// conform: tags=diagnostics
// conform: phase=check
fn f(value) Int => value
// expect-error: MS1000 3:6-3:11 parameter 'value' has no type; every parameter is written name Type, e.g. value Int
