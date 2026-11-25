// conform: tags=diagnostics
// conform: phase=check
interface Read {
    fn get() Int
}
type Box[T] {
    value T
}
impl Read for Box[fn(Int) Int] {
    fn get() Int {
        return 1
    }
}
impl Read for Box[fn(Int) Int] {
    fn get() Int {
        return 2
    }
}
// expect-error: MS1000 9:1-9:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 14:1-14:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
