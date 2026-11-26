// conform: tags=diagnostics
// conform: phase=check
interface Read[T] {
    fn get() Int
}
type Pair[A, B] {
    left A
    right B
}
impl Read[A] for Pair[A, A] {
    fn get() Int {
        return 1
    }
}
impl Read[A] for Pair[A, List[A]] {
    fn get() Int {
        return 2
    }
}
// expect-error: MS1000 10:1-10:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 15:1-15:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
