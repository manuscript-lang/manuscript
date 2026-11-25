// conform: tags=diagnostics
// conform: phase=check
enum Failure {
    NotFound
    Denied(reason String)
}
impl Error for Failure {
    fn message() String => "f"
}
fn classify(result: Result[Int, Failure]) Int {
    match result {
        error(NotFound) => return 1
        ok(value) => return value
    }
}
// expect-error: MS1000 7:1-7:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 10:19-10:20 remove the ':' between 'result' and its type; write result Type
// expect-fix: 10:19-10:20 ""
