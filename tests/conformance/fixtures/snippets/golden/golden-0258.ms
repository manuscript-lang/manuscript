// conform: tags=diagnostics
// conform: phase=check
interface I {
    fn m() Int
}
interface J {
    fn m() Int
}
type A {
    n Int
}
impl I for A {
    fn m() Int => return 1
}
impl J for A {
    fn m() Int => return 2
}
fn f(a: A) Int {
    return a.m()
}
// expect-error: MS1000 12:1-12:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 15:1-15:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
// expect-error: MS1000 18:7-18:8 remove the ':' between 'a' and its type; write a Type
// expect-fix: 18:7-18:8 ""
