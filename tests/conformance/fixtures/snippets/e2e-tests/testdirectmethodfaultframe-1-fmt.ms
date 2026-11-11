// conform: tags=control-flow,formatter,interfaces,parser,records,testing,tier-core
// conform: phase=parse
// conform: origin=tests/e2e/direct_methods_test.go:13 TestDirectMethodFaultFrame
interface Shape:
    fn area() Int

type Rect:
    w: Int
    h: Int

fn Rect.area() Int:
    return self.w * self.h

test "method fault frame":
    rect := Rect(w: 9223372036854775807, h: 2)
    rect.area()
