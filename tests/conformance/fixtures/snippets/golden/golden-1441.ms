// conform: tags=diagnostics
// conform: phase=check
interface Shape {
    fn area() Int
}

type Rect {
    w Int
    h Int
}

impl Shape for Rect {
    fn area() Int {
        return self.w * self.h
    }
}

test "method fault frame" {
    rect := Rect(w: 9223372036854775807, h: 2)
    rect.area()
}
// expect-error: MS1000 12:1-12:5 'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' when it changes self); a type satisfies an interface by having methods that match it, so nothing declares it
