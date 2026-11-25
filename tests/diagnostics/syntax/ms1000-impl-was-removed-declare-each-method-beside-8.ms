// conform: tags=diagnostics
// conform: phase=check
interface Same[V Equal] {
    fn same(other V) Bool
}
interface Read[V] {
    fn get() V
}
type Box[T] {
    value T
}
impl Same[T] for Box[T] {
    fn same(other: T) Bool {
        return self.value == other
    }
}
impl Read[T] for Box[T] {
    fn get() T {
        return self.value
    }
}
fn read[T](value: Box[T]) T {
    return value.get()
}
// expect-error: MS1000 12:1-12:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 17:1-17:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 22:17-22:18 remove the ':' between 'value' and its type; write value Type
// expect-fix: 22:17-22:18 ""
