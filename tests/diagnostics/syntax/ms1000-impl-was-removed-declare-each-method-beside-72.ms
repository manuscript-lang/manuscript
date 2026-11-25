// conform: tags=diagnostics
// conform: phase=check
type Counter {
    value Int
}
impl Counter {
    fn double() Int {
        return self.value * 2
    }
}
// expect-error: MS1000 6:1-6:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
