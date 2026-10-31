# conform: tags=control-flow,interfaces,records,testing,tier-core
# conform: phase=test
# conform: origin=tests/e2e/direct_methods_test.go:13 TestDirectMethodFaultFrame
interface Shape:
    fn area() Int

type Rect:
    w: Int
    h: Int

impl Shape for Rect:
    fn area() Int:
        return self.w * self.h

test "method fault frame":
    let rect = Rect(w: 9223372036854775807, h: 2)
    rect.area()
