// conform: tags=diagnostics
// conform: phase=check
type Box[Error Error] {
    cause Error
}
impl Error for Box[Error] {
    fn message() String => self.cause.message()
}
// expect-error: MS1000 6:1-6:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
