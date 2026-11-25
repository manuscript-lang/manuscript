// conform: tags=diagnostics
// conform: phase=check
type Cause {
    text String
}
impl Error for Cause {
    fn message() String => self.text
}
fn affine(n: Int) Result[Int, Cause] {
    if n < 0 {
        return error(Cause("negative"))
    }
    return ok(n + 1)
}
fn wrapped(n: Int) Result[Int, Cause] {
    value := affine(n)?
    return ok(value)
}
fn twice(n: Int) Result[Int, Cause] {
    value := wrapped(n)?
    return ok(value)
}
// expect-error: MS1000 6:1-6:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 9:12-9:13 remove the ':' between 'n' and its type; write n Type
// expect-fix: 9:12-9:13 ""
// expect-error: MS1000 15:13-15:14 remove the ':' between 'n' and its type; write n Type
// expect-fix: 15:13-15:14 ""
// expect-error: MS1000 19:11-19:12 remove the ':' between 'n' and its type; write n Type
// expect-fix: 19:11-19:12 ""
