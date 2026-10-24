# conform: tags=control-flow,formatter,interfaces,parser,records,testing,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/direct_methods_test.go:13 TestDirectMethodFaultFrame
interface Shape:
    def area() -> Int

type Rect:
    w: Int
    h: Int

impl Shape for Rect:
    def area() -> Int:
        return self.w * self.h

test "method fault frame":
    let rect = Rect(w: 9223372036854775807, h: 2)
    rect.area()
