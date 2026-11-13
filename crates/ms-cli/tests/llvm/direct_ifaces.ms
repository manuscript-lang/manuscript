interface Scorer:
    fn score(k: Int) Int
    fn scale(k: Float) Float

type Sq:
    side: Int

type Wide:
    w: Float
    h: Int

fn Sq.score(k: Int) Int: self.side * k + 1
fn Sq.scale(k: Float) Float: k * 2.0

fn Wide.score(k: Int) Int: self.h + k
fn Wide.scale(k: Float) Float: k + self.w

fn any_big(s: Scorer, n: Int) Bool:
    for i in 0..n:
        if s.score(i) > 100:
            return true
    return false

fn drive(s: Scorer, x: Float, n: Int) Float:
    var acc = x
    for i in 0..n:
        acc = acc + s.scale(acc * 0.001)
    return acc

fn longer(m: Map[Int, Int], n: Int) Bool:
    for i in 0..n:
        if m.length() > i:
            return true
    return false

fn lookups() Bool:
    var m = Map[Int, Int]()
    m.add(3, 30)
    m.add(4, 40)
    return longer(m, 1) and not longer(m, 0)

fn main() Unit:
    print(lookups())
    print(any_big(Sq(5), 4))
    print(any_big(Sq(5), 40))
    print(any_big(Wide(2.5, 3), 3))
    print(drive(Wide(1.5, 1), 2.0, 10))
    print(drive(Sq(1), 2.0, 10))
