// conform: tags=diagnostics
// conform: phase=check
interface Shape {
    fn area() Int
}
type Sq {
    s Int
}
impl Shape for Sq {
    fn area() Int => self.s * self.s
}
// expect-error: MS1000 9:1-9:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
