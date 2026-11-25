// conform: tags=diagnostics
// conform: phase=check
type Failure {
    code Int
}
impl Error for Failure {
    fn message() String => "failure"
}
fn failing() Result[Int, Failure] => error(Failure(code: 1))
fn count[T](r: Result[T, Error]) Int => 1
fn use() Int => count(r: failing())
// expect-error: MS1000 6:1-6:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 10:14-10:15 remove the ':' between 'r' and its type; write r Type
// expect-fix: 10:14-10:15 ""
