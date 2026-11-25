// conform: tags=diagnostics
// conform: phase=check
interface Read {
    fn get() Int
}
impl Read for E1 {
    fn get() Int => self.code
}
fn read[T](r: Result[T, Read]) Void => return
fn first() Void => read(f())
// expect-error: MS1000 6:1-6:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 9:13-9:14 remove the ':' between 'r' and its type; write r Type
// expect-fix: 9:13-9:14 ""
