// conform: tags=diagnostics
// conform: phase=check
export interface Read[T Equal] {
    fn get() T
}
type Box[T] {
    value T
}
impl Read[T] for Box[T] {
    fn get() T {
        return self.value
    }
}
// expect-error: MS1000 9:1-9:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
