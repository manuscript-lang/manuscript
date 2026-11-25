// conform: tags=diagnostics
// conform: phase=check
type List[T] {
}
impl List[T] {
    fn get() T
}
// expect-error: MS1000 5:1-5:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
