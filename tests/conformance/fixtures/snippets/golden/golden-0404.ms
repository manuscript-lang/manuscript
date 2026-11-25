// conform: tags=diagnostics
// conform: phase=check
type Key {
    id Int
}
impl Equal for Key {
    fn equals(other: Equal) Bool => return true
}
fn keys() Map[Key, Int] => return Map[Key, Int]()
// expect-error: MS1000 6:1-6:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
