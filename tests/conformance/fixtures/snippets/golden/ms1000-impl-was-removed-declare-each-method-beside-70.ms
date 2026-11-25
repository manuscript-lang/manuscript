// conform: tags=diagnostics
// conform: phase=check
type List[T] { ... }
impl List[T] {
    fn map[U](transform: fn(T) U) List[U] { ... }
    fn length() Int { ... }
}
// expect-error: MS1000 4:1-4:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
