// conform: tags=diagnostics
// conform: phase=check
type B {
    x Int
}
impl B {
    fn m() Int {
        return 1
    }
}
impl B {
    fn m() Int {
        return 2
    }
}
// expect-error: MS1000 6:1-6:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 11:1-11:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
