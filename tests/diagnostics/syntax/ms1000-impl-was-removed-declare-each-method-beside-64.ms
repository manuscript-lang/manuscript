// conform: tags=diagnostics
// conform: phase=check
interface I[T] {
    fn f(x I[List[T]]) Int
}

type Box[T] {
    v T
}
impl I[T] for Box[T] {
    fn f(x: I[List[T]]) Int {
        return 1
    }
}
fn main() Void {
    b := Box[Int](v: 1)
    i := I[Int](value: b)
}
// expect-error: MS1000 10:1-10:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
