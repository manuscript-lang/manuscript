# conform: tags=control-flow,faults,formatter,interfaces,modules,mutation,parser,records,stdlib-cleanup,tier-stdlib,with-cleanup
# conform: phase=parse
# conform: origin=tests/e2e/match_bounds_test.go:32 TestBoundedMatchNative
import Closeable from "@std/core.ms"
type Count:
    total: Int
type Watch:
    count: Count
impl Closeable for Watch:
    fn close() Unit:
        self.count.total += 10
fn next(count: Count) Int:
    with watch = Watch(count):
        count.total += 1
        return 0
fn unknown(s: Shape) Int: return area(s)
export fn main() Int:
    let shapes = [Shape.Circle(2), Shape.Square(3), Shape.Tri(4)]
    let count = Count(0)
    if area(shapes.get(next(count) * 0)) != 6: return 1
    if count.total != 11: return 2
    if area(shapes.get(next(count))) != 6: return 5
    if count.total != 22: return 6
    if unknown(Shape.Tri(4)) != 4: return 3
    var sum = 0
    var i = 0
    while i < 321:
        sum += area(shapes.get(i % 3))
        i += 1
    if sum != 2033: return 4
    return 0
