// conform: tags=diagnostics
// conform: phase=check
type Options {
    required Int
    count Int = 3
}
fn read() Options {
    return Options(required: 1, |)
}
// expect-error: MS1000 8:33-8:34 expected an expression, found '|'; write a value, name, call, or literal here
