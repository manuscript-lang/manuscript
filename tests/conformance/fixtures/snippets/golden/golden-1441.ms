// conform: tags=diagnostics
// conform: phase=check
interface Shape:
    fn area() Int

type Rect:
    w: Int
    h: Int

impl Shape for Rect:
    fn area() Int:
        return self.w * self.h

test "method fault frame":
    rect := Rect(w: 9223372036854775807, h: 2)
    rect.area()
