// conform: tags=diagnostics
// conform: phase=check
type Key%d {
    value: Int
}
impl Tag for Key%d {
    fn tag() Int => self.value
}
// expect-error: MS1000 3:9-3:10 expected '{', found '%'; block headers (fn, if, else, for, while, match, type, enum, interface, test) end with '{' on the same line, and the block closes with '}'
// expect-error: MS1000 6:1-6:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
