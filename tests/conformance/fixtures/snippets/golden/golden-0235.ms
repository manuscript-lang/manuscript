// conform: tags=diagnostics
// conform: phase=check
interface I {
    fn n() Int
}
type Pair[A, B] {
    a A
    b B
}
impl I for Pair[A, A] {
    fn n() Int {
        return 1
    }
}
export fn main() Int {
    return I(value: Pair[Int, String](a: 1, b: "x")).n()
}
// expect-error: MS1000 10:1-10:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
