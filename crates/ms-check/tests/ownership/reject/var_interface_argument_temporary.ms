interface Sink:
    var fn push(x: Int) Unit

type Items:
    xs: List[Int]

impl Sink for Items:
    var fn push(x: Int) Unit: self.xs.append(x)

fn fill(var s: Sink) Unit:
    s.push(1)

fn main() Int:
    var items = Items(List[Int]())
    fill(var items)  # error: would be converted to a temporary Sink
    return items.xs.length()
