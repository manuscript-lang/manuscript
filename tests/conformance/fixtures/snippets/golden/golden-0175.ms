// conform: tags=diagnostics
// conform: phase=check
type Cause[T] {
    detail T
}
impl Error for Cause[T] {
    fn message() String => self.detail.to_string()
}
fn identity[T](value: T) T => value
fn consume[T](value: T, cause: Error, optional: T?) Void => return
fn first() Void => consume(value: 1, cause: identity(Cause(2)), optional: identity(3))
// expect-error: MS1000 6:1-6:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 9:21-9:22 remove the ':' between 'value' and its type; write value Type
// expect-fix: 9:21-9:22 ""
// expect-error: MS1000 10:20-10:21 remove the ':' between 'value' and its type; write value Type
// expect-fix: 10:20-10:21 ""
