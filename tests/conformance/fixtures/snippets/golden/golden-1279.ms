// conform: tags=diagnostics
// conform: phase=check
// α😀
interface Read {
    fn get() Int
}
type Box {
    value Int // 😀é
}
impl Read for Box {
    fn get() Int {
        return self.value
    }
}
fn neighbor() Int => 1
// expect-error: MS1000 10:1-10:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
