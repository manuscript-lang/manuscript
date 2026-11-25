// conform: tags=diagnostics
// conform: phase=check
interface Read[T] {
    fn get() T
}
type Box[T] {
    item T
}
impl Read[T] for Box[T] {
    fn get() T => self.item
}
fn read() Read[Int] => Box(1)
// expect-error: MS1000 9:1-9:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
