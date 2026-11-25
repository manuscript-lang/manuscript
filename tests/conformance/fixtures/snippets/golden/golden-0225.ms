// conform: tags=diagnostics
// conform: phase=check
impl Error for Result[Int] {
    fn message() String {
        return "x"
    }
}
fn f(x: Result[Int]) Result[Int, Error] {
    return error(x)
}
// expect-error: MS1000 3:1-3:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 8:7-8:8 remove the ':' between 'x' and its type; write x Type
// expect-fix: 8:7-8:8 ""
