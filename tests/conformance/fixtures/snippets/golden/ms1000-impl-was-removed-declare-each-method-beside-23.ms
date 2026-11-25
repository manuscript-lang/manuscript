// conform: tags=diagnostics
// conform: phase=check
impl Error for Result {
    fn message() String {
        return "x"
    }
}
fn general(value: Result) Error {
    return value
}
// expect-error: MS1000 3:1-3:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 8:17-8:18 remove the ':' between 'value' and its type; write value Type
// expect-fix: 8:17-8:18 ""
