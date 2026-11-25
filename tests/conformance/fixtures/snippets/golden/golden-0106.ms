// conform: tags=diagnostics
// conform: phase=check
interface Same[V Equal] {
    fn same(other V) Bool
}
type Box[T] {
    value T
}
impl Same[T] for Box[T] {
    fn same(other: T) Bool {
        return self.value == other
    }
}
fn compare[T](value: Box[T], other: T) Bool {
    return value.same(other: other)
}
// expect-error: MS1000 9:1-9:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 14:20-14:21 remove the ':' between 'value' and its type; write value Type
// expect-fix: 14:20-14:21 ""
