# conform: tags=control-flow,formatter,interfaces,lists,modules,mutation,parser,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/interface-method-calls-cache-each-receiver-type.ms
import expect_true from "@std/test.ms"

interface Shape:
    fn area(scale: Int) Int

type Sq:
    side: Int

type Rect:
    w: Int
    h: Int

type Tri:
    b: Int
    h: Int

impl Shape for Sq:
    fn area(scale: Int) Int: self.side * self.side * scale

impl Shape for Rect:
    fn area(scale: Int) Int: self.w * self.h * scale

impl Shape for Tri:
    fn area(scale: Int) Int: self.b * self.h * scale / 2

fn measure(shape: Shape, scale: Int) Int: shape.area(scale: scale)

test "three receiver types alternate at one site":
    let shapes: List[Shape] = [Sq(side: 3), Rect(w: 2, h: 5), Tri(b: 4, h: 5)]
    var total = 0
    var round = 0

    while round < 4:
        var i = 0

        while i < 3:
            total = total + measure(shape: shapes[i], scale: 2)
            i = i + 1

        round = round + 1

    try expect_true((total == 4 * (18 + 20 + 20)))
