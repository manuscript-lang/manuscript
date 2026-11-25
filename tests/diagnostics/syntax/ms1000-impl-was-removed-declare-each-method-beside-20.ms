// conform: tags=diagnostics
// conform: phase=check
type Failure {
    detail String
}
impl Error for Failure {
    fn message() String => self.detail
}
fn fail_cause[T, E: Error](cause: E) Result[T, E]: error(cause)
fn first() Result[Int, Error] => fail_cause(Failure("empty"))
// expect-error: MS1000 6:1-6:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 9:19-9:20 a type parameter's bound follows its name without ':'; write E Comparable
// expect-fix: 9:19-9:20 ""
